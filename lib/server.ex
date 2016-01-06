defmodule CoopCache.Server do
  require Logger

  use GenServer

  def start_link(name, options) do
    GenServer.start_link(__MODULE__, [name, options], name: name)
  end

  def reset(name, version) do
    GenServer.call(name, {:reset, version})
  end

  def data(name) do
    version    = GenServer.call(name, {:version})
    data       = :ets.tab2list(name)
    {version, data}
  end

  def version(name) do
    GenServer.call(name, {:version})
  end

  def init([name, %{memory_limit: memory_limit, version: version, callback_module: callback_module }]) when is_atom(name) and is_integer(memory_limit) do
    nodes = Application.get_env(:coop_cache, :nodes) -- [node]
    Enum.each(nodes, fn(node) -> :net_adm.ping(node) end)
    data  = :ets.new(name, [:named_table, :set, {:read_concurrency, true}])
    locks = :ets.new(:locks, [:set])
    subs  = :ets.new(:subs,  [:bag])
    state = %{
      name: name,
      data: data, locks: locks, subs: subs,
      nodes: nodes,
      memory_limit: memory_limit,
      version: version,
      callback_module: callback_module,
      full: false
    }
    send(self, :prime)
    {:ok, state}
  end

  def handle_call({:write_or_wait, key, fun}, from,
    state = %{ name: name, data: data, locks: locks, subs: subs, nodes: nodes, full: full, version: version }) do
    case :ets.lookup(locks, key) do
      [{key, _}] ->
          # processing is in progress
          # we subscribe
          :ets.insert(subs,  {key, from})
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
                :ets.insert(subs,  {key, from})
                spawn(__MODULE__, :process_async, [key, fun, self(), name, nodes, version])
              true ->
                GenServer.reply(from, {:error, :cache_full})
            end
        end
    end
    {:noreply, state}
  end

  def handle_call({:reset, version}, _, state) do
    {:reply, :ok, reset_state(state, version)}
  end

  def handle_call({:version}, _, state = %{version: version}) do
    {:reply, version, state}
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

  def handle_info({:value, key, value, version}, state = %{ data: data, locks: locks, subs: subs, memory_limit: memory_limit, version: version }) do
    # this might be a value arriving from remote
    # while the local value was already written
    case :ets.lookup(data, key) do
      [] ->
        # insert the actual data
        :ets.insert(data, {key, value})
        # publish data to all subscribers
        Enum.each(
          :ets.lookup(subs, key),
          fn({_, subscriber}) -> GenServer.reply(subscriber, value) end
        )
        # claen up
        :ets.delete(subs, key)
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

  def handle_info({:value, _, _, _non_mathing_version}, state) do
    {:noreply, state}
  end

  def handle_info({:reset, version}, state) do
    {:noreply, reset_state(state, version)}
  end

  def handle_info(:prime, state = %{name: name, nodes: nodes, data: data}) do
    case aquire_data(name, Enum.shuffle(nodes)) do
      nil ->
        {:noreply, state}
      {version, remote_data} ->
        :ets.insert(data, remote_data)
        {:noreply, %{state | version: version}}
    end
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
      {version, data} ->
        {version, data}
     end
  end

  def process_async(key, fun, sender, name, nodes, version) do
    value   = fun.()
    message = {:value, key, value, version}
    send(sender, message)
    send_to_all(name, nodes, message)
  end


  # we are already at the newest version
  def reset_state(state = %{version: version}, version) do
    state
  end

  def reset_state(state = %{nodes: nodes, name: name, data: data, locks: locks, callback_module: callback_module}, version) do
    # let the callback know of the reset
    case callback_module do
      nil -> :noop
      _   -> :ok = callback_module.reset(version)
    end
    # tell the peers
    send_to_all(name, nodes, {:reset, version})
    # we need to recalculate everything that is in flight
    Enum.each(
      :ets.tab2list(locks),
      fn({key, fun}) ->
        spawn(__MODULE__, :process_async, [key, fun, self(), name, nodes, version])
      end
    )
    :ets.delete_all_objects(data)
    Map.merge( state, %{ full: false, version: version } )
  end


  def send_to_all(name, nodes, message) do
    Enum.each(nodes, fn(node) -> send({name, node}, message) end)
  end

end
