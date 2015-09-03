defmodule CoopCache.Server do
  require Logger

  use GenServer

  def start_link(name, options) do
    GenServer.start_link(__MODULE__, [name, options], name: table_name(name))
  end

  def reset(name) do
    GenServer.call(table_name(name), :reset)
  end

  def init([name, %{memory_limit: memory_limit}]) when is_atom(name) and is_integer(memory_limit) do
    nodes = Application.get_env(:coop_cache, :nodes) -- [node]
    Enum.each(nodes, fn(node) -> :net_adm.ping(node) end)
    data  = :ets.new(table_name(name), [:named_table, :set, {:read_concurrency, true}])
    locks = :ets.new(:locks, [:set])
    subs  = :ets.new(:subs,  [:bag])
    state = %{
      name: name,
      data: data, locks: locks, subs: subs,
      nodes: nodes,
      memory_limit: memory_limit,
      full: false, reset_index: 0
    }
    {:ok, state}
  end

  def handle_call({:write_or_wait, key, fun}, from,
    state = %{ name: name, data: data, locks: locks, subs: subs, nodes: nodes, full: full, reset_index: reset_index }) do
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
                  IO.puts("send lock: #{inspect({node, table_name(name)})}")
                  send({table_name(name), node}, {:lock, key, fun})
                  end)
                :ets.insert(subs,  {key, from})
                spawn(__MODULE__, :process_async, [key, fun, self(), name, nodes, reset_index])
              true ->
                IO.puts("full, not writing")
                GenServer.reply(from, {:error, :cache_full})
            end
        end
    end
    {:noreply, state}
  end

  def handle_call(:reset, _, state = %{ name: name, data: data, locks: locks, nodes: nodes, reset_index: reset_index }) do
    reset_index = reset_index + 1
    # we need to recalculate everything that is in flight
    Enum.each(
      :ets.tab2list(locks),
      fn({key, fun}) ->
        spawn(__MODULE__, :process_async, [key, fun, self(), name, nodes, reset_index])
      end
    )
    :ets.delete_all_objects(data)
    reset_state = Map.merge( state, %{ full: false, reset_index: reset_index } )
    {:reply, :ok, reset_state}
  end

  ## this is for testing
  def handle_call(:state, _, state = %{ data: data, locks: locks, subs: subs}) do
    {:reply, Map.merge(state, %{ data: :ets.tab2list(data), locks: :ets.tab2list(locks), subs: :ets.tab2list(subs)}), state}
  end

  def handle_info({:lock, key, fun}, state = %{ locks: locks }) do
    IO.puts("remote lock: #{inspect({key})}")
    :ets.insert(locks, {key, fun})
    {:noreply, state}
  end

  def handle_info({:value, key, value, reset_index}, state = %{ data: data, locks: locks, subs: subs, memory_limit: memory_limit, reset_index: reset_index }) do
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
    IO.puts("menory #{:ets.info(data, :memory)} >= #{memory_limit}")
    case :ets.info(data, :memory) >= memory_limit do
      true ->
        Logger.error("cache #{data} reached limit of #{memory_limit} Bytes.")
        {:noreply, %{ state | full: true }}
      false ->
        {:noreply, state}
    end
  end

  def handle_info({:value, _, _, _non_mathing_reset_index}, state) do
    {:noreply, state}
  end

  def handle_info(msg, state) do
    IO.puts("unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  def process_async(key, fun, sender, name, nodes, reset_index) do
    value   = fun.()
    message = {:value, key, value, reset_index}
    send(sender, message)
    Enum.each(nodes, fn(node) -> send({table_name(name), node}, message) end)
  end

  def table_name(name) do
    String.to_atom(Atom.to_string(name) <> "_cache")
  end

end
