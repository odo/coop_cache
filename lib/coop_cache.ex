defmodule CoopCache do

  use GenServer

  def start(name)  do
    GenServer.start_link(__MODULE__, name, name: table_name(name))
  end

  def cached(name, key, fun) do
    case :ets.lookup(table_name(name), key) do
      [] ->
        GenServer.call(table_name(name), {:write_or_wait, key, fun})
      [{_, value}] ->
        IO.puts("cache hit")
        value
    end
  end

  def init(name) do
    data  = :ets.new(table_name(name), [:named_table, :bag, {:read_concurrency, true}])
    locks = :ets.new(:locks, [:bag])
    subs  = :ets.new(:subs, [:bag])
    state = %{ data: data, locks: locks, subs: subs  }
    {:ok, state}
  end

  def handle_call({:write_or_wait, key, fun}, from, state = %{ data: data, locks: locks, subs: subs }) do
    case :ets.lookup(locks, key) do
      [{key}] ->
          # processing is in progress
          # we subscribe
          :ets.insert(subs,  {key, from})
      [] ->
        case :ets.lookup(data, key) do
          [{_, value}] ->
            # we did not see the result outside the process
            # but now processing is done
            # we reply directly
            GenServer.reply(from, value)
          [] ->
            # the key is completely new
            # lock, subscribe and spawn
            :ets.insert(locks, {key})
            :ets.insert(subs,  {key, from})
            spawn(__MODULE__, :process_async, [key, fun, self()])
        end
    end
    {:noreply, state}
  end

  def handle_call(:state, _, state = %{ data: data, locks: locks, subs: subs}) do
    {:reply, %{ data: :ets.tab2list(data), locks: :ets.tab2list(locks), subs: :ets.tab2list(subs)}, state}
  end

  def handle_info({:value, key, value}, state = %{ data: data, locks: locks, subs: subs }) do
    :ets.insert(data, {key, value})
    Enum.each(
      :ets.lookup(subs, key),
      fn({_, from}) -> GenServer.reply(from, value) end
    )
    :ets.delete(subs, key)
    :ets.delete(locks, key)
    {:noreply, state}
  end

  def process_async(key, fun, sender) do
    value = fun.()
    send(sender, {:value, key, value})
  end

  def table_name(name) do
    String.to_atom(Atom.to_string(name) <> "_cache")
  end

end
