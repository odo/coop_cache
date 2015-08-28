defmodule CoopCacheTest do
  use ExUnit.Case

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

  test "mass insertion" do
    test_count = 100
    CoopCache.start(:test)
    # do inserts
    Enum.each(Enum.to_list(1..test_count), fn(_) -> spawn(__MODULE__, :insert_and_reply, [self()] ) end )
    # see if exactly all clients got the value
    Enum.each(Enum.to_list(1..test_count), fn(_) -> assert true == wait_for({:value, :test_value}) end )
    assert false == wait_for({:value, :test_value}, 0)
    # see if it was only processed once
    assert true  == wait_for(:processed)
    assert false == wait_for(:processed, 0)
    assert %{data: [key: :test_value], locks: [], subs: []} == GenServer.call(:test_cache, :state)
  end

  def insert_and_reply(from) do
    fun = fn() ->
      :timer.sleep(50)
      send(from, :processed)
      :test_value
    end
    value = CoopCache.cached(:test, :key, fun)
    send(from, {:value, value})
  end

end
