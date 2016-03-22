defmodule CoopCache.Server do
  require Logger

  use GenServer

  def start_link(name, options) do
    GenServer.start_link(__MODULE__, [name, options], name: name)
  end

  def set_nodes(name, nodes) do
    GenServer.call(name, {:set_nodes, nodes})
  end

  def data(name) do
    :ets.tab2list(name)
  end

  def init([name, %{memory_limit: memory_limit, cache_duration: cache_duration }]) when is_atom(name) and is_integer(memory_limit) do
    (nodes = Application.get_env(:coop_cache, :nodes) -- [node])
    |> Enum.each(&:net_adm.ping/1)
    data     = :ets.new(name, [:named_table, :set, {:read_concurrency, true}])
    activity = :ets.new(:activity, [:set])
    locks    = :ets.new(:locks,    [:set])
    subs     = :ets.new(:subs,     [:bag])
    state    = %{
      name: name,
      data: data, locks: locks, subs: subs, activity: activity,
      nodes: nodes,
      memory_limit: memory_limit,
      full: false
    }
    send(self, :prime)
    send(self, {:clear_cache, cache_duration})
    {:ok, state}
  end

  def handle_call({:write_or_wait, key, fun}, from,
    state = %{ name: name, data: data, locks: locks, subs: subs, activity: activity, nodes: nodes, full: full }) do
    :ets.insert(activity, {key, now})
    case :ets.lookup(locks, key) do
      [{key, _}] ->
          # processing is in progress
          # we subscribe
          :ets.insert(subs, {key, from})
      [] ->
        case :ets.lookup(data, key) do
          [{_, value}] ->
            # we did not see the result outside the process
            # but now processing is done so
            # we reply directly
            GenServer.reply(from, value)
          [] ->
            case full do
              false ->
                # the key is completely new
                # lock, subscribe and spawn
                :ets.insert(locks, {key, fun})
                Enum.each(nodes, fn(node) ->
                  send({name, node}, {:lock, key, fun})
                  end)
                :ets.insert(subs, {key, from})
                spawn(__MODULE__, :process_async, [key, fun, self(), name, nodes])
              true ->
                GenServer.reply(from, {:error, :cache_full})
            end
        end
    end
    {:noreply, state}
  end

  def handle_call({:set_nodes, nodes}, _, state) do
    {:reply, :ok, %{state | nodes: (nodes  -- [node])}}
  end

  ## this is for testing
  def handle_call(:state, _, state = %{ data: data, locks: locks, subs: subs}) do
    {:reply, Map.merge(state, %{ data: :ets.tab2list(data), locks: :ets.tab2list(locks), subs: :ets.tab2list(subs)}), state}
  end

  def handle_info({:lock, key, fun}, state = %{ data: data, locks: locks }) do
    case {:ets.lookup(locks, key), :ets.lookup(data, key)}  do
      {[], []} ->
        :ets.insert(locks, {key, fun})
      _  ->
        :noop
    end
    {:noreply, state}
  end

  def handle_cast({:activity, key}, state = %{activity: activity}) do
    :ets.insert(activity, {key, now})
    {:noreply, state}
  end

  def handle_info({:value, key, value}, state = %{ data: data, locks: locks, subs: subs, memory_limit: memory_limit}) do
    # this might be a value arriving from remote
    # while the local value was already written
    case :ets.lookup(data, key) do
      [] ->
        # insert the actual data
        :ets.insert(data, {key, value})
        # publish data to all subscribers
        :ets.lookup(subs, key)
        |> Enum.each( fn({_, subscriber}) -> GenServer.reply(subscriber, value) end )
        # clean up
        :ets.delete(subs,  key)
        :ets.delete(locks, key)
        # see if cache is full
        case :ets.info(data, :memory) >= memory_limit do
          true ->
            Logger.error("cache #{data} reached limit of #{memory_limit} Bytes.")
            {:noreply, %{ state | full: true }}
          false ->
            {:noreply, state}
        end
      _ ->
        {:noreply, state}
    end
  end

  def handle_info(:prime, state = %{name: name, nodes: nodes, data: data}) do
    case aquire_data(name, Enum.shuffle(nodes)) do
      nil ->
        {:noreply, state}
      remote_data ->
        :ets.insert(data, remote_data)
        {:noreply, state}
    end
  end

  def handle_info({:clear_cache, duration}, state = %{data: data, locks: locks, subs: subs, activity: activity}) do
    Enum.max([1, round(duration/10)]) * 1000
    |> :erlang.send_after(self, {:clear_cache, duration})

    expire_at = now - duration
    :ets.select(activity, [{ {:"$1", :"$2"}, [{:<, :"$2", expire_at}], [:"$1"] }])
    |> Enum.each(
      fn(key) ->
        [locks, subs, activity, data]
        |> Enum.each(fn(table) -> :ets.delete(table, key) end)
      end
    )
    {:noreply, state}
  end

  def handle_info(msg, state) do
    Logger.error("unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  def aquire_data(_, []) do
    nil
  end

  def aquire_data(name, [next_node | rest]) do
    case :rpc.call(next_node, __MODULE__, :data, [name]) do
      {:badrpc, _} ->
        aquire_data(name, rest)
      data ->
        data
     end
  end

  def process_async(key, fun, sender, name, nodes) do
    # this is the actual computation of the value
    value   = fun.()
    message = {:value, key, value}
    send(sender, message)
    send_to_all(name, nodes, message)
  end

  def send_to_all(name, nodes, message) do
    Enum.each(nodes, fn(node) -> send({name, node}, message) end)
  end

  def now do
    :erlang.system_time(:seconds)
  end

end
