defmodule CoopCache do
  require Logger

  use GenServer

  defmacro cached(name, key, do: block) do
    quote do
      name = table_name(unquote(name))
      key  = unquote(key)
      fun  = fn() ->
        unquote(block)
      end

      case :ets.lookup(name, key) do
        [] ->
          case GenServer.call(name, {:write_or_wait, key, fun}) do
            {:error, :cache_full} ->
              fun.()
            value ->
              value
          end
        [{_, value}] ->
          value
      end

    end
  end

  def start_link(name, options) do
    GenServer.start_link(__MODULE__, [name, options], name: table_name(name))
  end

  def reset(name) do
    GenServer.call(table_name(name), :reset)
  end

  def init([name, %{memory_limit: memory_limit}]) when is_atom(name) and is_integer(memory_limit) do
    data  = :ets.new(table_name(name), [:named_table, :set, {:read_concurrency, true}])
    locks = :ets.new(:locks, [:set])
    subs  = :ets.new(:subs,  [:bag])
    state = %{ data: data, locks: locks, subs: subs, memory_limit: memory_limit, full: false, reset_index: 0 }
    {:ok, state}
  end

  def handle_call({:write_or_wait, key, fun}, from, state = %{ data: data, locks: locks, subs: subs, full: full, reset_index: reset_index }) do
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
                :ets.insert(subs,  {key, from})
                spawn(__MODULE__, :process_async, [key, fun, self(), reset_index])
              true ->
                GenServer.reply(from, {:error, :cache_full})
            end
        end
    end
    {:noreply, state}
  end

  def handle_call(:reset, _, state = %{ data: data, locks: locks, subs: subs, reset_index: reset_index }) do
    reset_index = reset_index + 1
    # we need to recalculate everything that is in flight
    Enum.each(
      :ets.tab2list(locks),
      fn({key, fun}) ->
        spawn(__MODULE__, :process_async, [key, fun, self(), reset_index])
      end
    )
    :ets.delete_all_objects(data)
    reset_state = Map.merge(
      state,
      %{
        full: false,
        reset_index: reset_index
      }
    )
    {:reply, :ok, reset_state}
  end

  def handle_call(:state, _, state = %{ data: data, locks: locks, subs: subs}) do
    {:reply, Map.merge(state, %{ data: :ets.tab2list(data), locks: :ets.tab2list(locks), subs: :ets.tab2list(subs)}), state}
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
    case :ets.info(data, :memory) >= memory_limit do
      true ->
        Logger.error("cache #{data} reached limit of #{memory_limit} Bytes.")
        {:noreply, %{ state | full: true }}
      false ->
        {:noreply, state}
    end
  end

  def handle_info({:value, key, value, reset_index}, state) do
    {:noreply, state}
  end

  def process_async(key, fun, sender, reset_index) do
    value = fun.()
    send(sender, {:value, key, value, reset_index})
  end

  def table_name(name) do
    String.to_atom(Atom.to_string(name) <> "_cache")
  end

end
