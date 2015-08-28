defmodule CoopCache do

  use GenServer

  def start(name)  do
    {:ok, pid} = GenServer.start_link(__MODULE__, name, name: table_name(name))
    pid
  end

  def cached(name, key, fun) do
    case :ets.lookup(table_name(name), key) do
      [] ->
        GenServer.call(table_name(name), {:write, key, fun})
      [{key, value}] ->
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

  def handle_call({:write, key, fun}, from, state = %{ locks: locks, subs: subs }) do
    case :ets.lookup(locks, key) do
      [{key}] ->
        :ets.insert(subs,  {key, from})
      [] ->
        :ets.insert(locks, {key})
        :ets.insert(subs,  {key, from})
        spawn(__MODULE__, :process_async, [key, fun, self()])
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
      fn({key, from}) -> GenServer.reply(from, value) end
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
