defmodule CoopCache.ServerTest do
  use ExUnit.Case, async: false
  import CoopCache

  defmacro wait_for(msg, timeout \\ 1000) do
    quote do
      receive do
        unquote(msg) ->
          true
      after
        unquote(timeout) ->
          false
      end
    end
  end

  setup do
    case :erlang.whereis(:test_cache) do
      :undefined -> :noop
      pid        -> :erlang.exit(pid, :ok)
    end
    :ok
  end

  test "mass insertion" do
    test_count = 1000
    CoopCache.Server.start_link(:test, %{ memory_limit: 1000000, version: 1})
    # do inserts
    Enum.each(Enum.to_list(1..test_count), fn(_) -> spawn(__MODULE__, :insert_and_reply, [self()] ) end )
    # see if exactly all clients got the value
    Enum.each(Enum.to_list(1..test_count), fn(_) -> assert true == wait_for({:value, :test_value}) end )
    assert false == wait_for({:value, :test_value}, 0)
    # see if it was only processed once
    assert true  == wait_for({:processed, :test_value})
    assert false == wait_for({:processed, :test_value}, 0)
    # state should be clean
    state = GenServer.call(:test_cache, :state)
    assert [test: :test_value] == state.data
    assert [] == state.locks
    assert [] == state.subs
    # test a few cache hits
    Enum.each(Enum.to_list(1..10), fn(_) -> spawn(__MODULE__, :insert_and_reply, [self()] ) end )
    # see if exactly all clients got the value
    Enum.each(Enum.to_list(1..10), fn(_) -> assert true == wait_for({:value, :test_value}) end )
  end

  test "resetting" do
    CoopCache.Server.start_link(:test, %{ memory_limit: 1000000, version: 1})
    # do insert
    Application.put_env(:test, :test, :before_test)
    fun = fn() -> Application.get_env(:test, :test) end
    spawn(__MODULE__, :insert_and_reply, [self(), {:reset_key, fun}, 10])
    :timer.sleep(5)
    Application.put_env(:test, :test, :after_test)
    CoopCache.Server.reset(:test, 2)
    assert true == wait_for({:value, :after_test})
  end

  test "memory_limit" do
    {:ok, _} = CoopCache.Server.start_link(:test, %{ memory_limit: 0, version: 1})
    spawn(__MODULE__, :insert_and_reply, [self(), {:key1, :test_value1}] )
    assert true  == wait_for({:processed, :test_value1})
    assert true == wait_for({:value, :test_value1})
    spawn(__MODULE__, :insert_and_reply, [self(), {:key2, :test_value2}] )
    assert true == wait_for({:value, :test_value2})
    assert false == wait_for({:processed, :test_value1}, 1)
    assert true  == wait_for({:processed, :test_value2})
    assert false == wait_for({:processed, :test_value2}, 1)
    # state should be clean
    state = GenServer.call(:test_cache, :state)
    assert [key1: :test_value1] == state.data
    assert [] == state.locks
    assert [] == state.subs
  end

  # * local lock, local subscribe
  # * local value
  # * remote lock
  # * remote value
  test "distribution 1" do
    never = fn() -> :timer.sleep(1000000) end
    {:ok, state_init}      = CoopCache.Server.init([:test, %{memory_limit: 100000, version: 1}])

    {:noreply, state_llls} = CoopCache.Server.handle_call({:write_or_wait, :key, never}, {self(), :ref}, state_init)

    {:noreply, state_lv}   = CoopCache.Server.handle_info({:value, :key, :value_local, 1}, state_llls)
    # from here on, nothing should change
    assert true == wait_for({:ref, :value_local})
    snapshot_lv = snapshot_state(state_lv)

    {:noreply, state_rl}   = CoopCache.Server.handle_info({:lock, :key, never}, state_lv)
    snapshot_rl = snapshot_state(state_rl)
    assert snapshot_rl == snapshot_lv

    {:noreply, state_rv}   = CoopCache.Server.handle_info({:value, :key, :value_remote, 1}, state_rl)
    snapshot_rv = snapshot_state(state_rv)
    assert snapshot_lv == snapshot_rv
  end

  # * local lock, local subscribe
  # * remote lock
  # * local value
  # * remote value
  test "distribution 2" do
    never = fn() -> :timer.sleep(1000000) end
    {:ok, state_init}      = CoopCache.Server.init([:test, %{memory_limit: 100000, version: 1}])

    {:noreply, state_llls} = CoopCache.Server.handle_call({:write_or_wait, :key, never}, {self(), :ref}, state_init)
    snapshot_llls = snapshot_state(state_llls)
    assert [key: _] = snapshot_llls.locks

    {:noreply, state_rl}   = CoopCache.Server.handle_info({:lock, :key, never}, state_llls)
    snapshot_rl = snapshot_state(state_rl)
    assert snapshot_rl == snapshot_llls

    {:noreply, state_lv}   = CoopCache.Server.handle_info({:value, :key, :value_local, 1}, state_rl)
    assert true == wait_for({:ref, :value_local})
    snapshot_lv = snapshot_state(state_lv)
    assert []                   == snapshot_lv.locks
    assert [key: :value_local] == snapshot_lv.data

    {:noreply, state_rv}   = CoopCache.Server.handle_info({:value, :key, :value_remote, 1}, state_lv)
    snapshot_rv = snapshot_state(state_rv)
    assert snapshot_lv == snapshot_rv
  end

  # * local lock, local subscribe
  # * remote lock
  # * remote value
  # * local value
  test "distribution 3" do
    never = fn() -> :timer.sleep(1000000) end
    {:ok, state_init}      = CoopCache.Server.init([:test, %{memory_limit: 100000, version: 1}])

    {:noreply, state_llls} = CoopCache.Server.handle_call({:write_or_wait, :key, never}, {self(), :ref}, state_init)
    snapshot_llls = snapshot_state(state_llls)
    assert [key: _] = snapshot_llls.locks

    {:noreply, state_rl}   = CoopCache.Server.handle_info({:lock, :key, never}, state_llls)
    snapshot_rl = snapshot_state(state_rl)
    assert snapshot_rl == snapshot_llls

    {:noreply, state_rv}   = CoopCache.Server.handle_info({:value, :key, :value_remote, 1}, state_rl)
    assert true == wait_for({:ref, :value_remote})
    snapshot_rv = snapshot_state(state_rv)
    assert []                   == snapshot_rv.locks
    assert [key: :value_remote] == snapshot_rv.data

    {:noreply, state_lv}   = CoopCache.Server.handle_info({:value, :key, :value_local, 1}, state_rv)
    snapshot_lv = snapshot_state(state_lv)
    assert snapshot_lv == snapshot_rv
  end

  def snapshot_state(state  = %{ data: data, locks: locks, subs: subs}) do
    Map.merge(state, %{ data: :ets.tab2list(data), locks: :ets.tab2list(locks), subs: :ets.tab2list(subs)})
  end

  def insert_and_reply(from, {key, data} \\ {:test, :test_value}, sleep_for \\ 1) do
    value =
    cached(:test, key) do
      result =
      case is_function(data) do
        true  -> data.()
        false -> data
      end
      :timer.sleep(sleep_for)
      send(from, {:processed, result})
      result
    end
    send(from, {:value, value})
  end

end
