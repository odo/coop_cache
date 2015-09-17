defmodule CoopCache.ServerConcurrencyTest do
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
    Application.ensure_all_started(:flock)
    on_exit fn ->
      Flock.Server.stop_all
    end
    :ok
  end

  @node_config %{config: "config/concurrency_test_config.exs", apps: [:coop_cache]}

  def start_nodes(names) do
    Flock.Server.start_nodes(names, @node_config)
    |> Enum.map(fn(node) ->
      :rpc.call(node, Code, :eval_file, ["test/test_client.ex"])
      node
    end)
  end

  test "cooperation" do
    start_nodes([:one, :two, :three, :four, :five])
    |> Enum.map( fn(node) ->
        :timer.sleep(1)
        Enum.map(1..5, fn(_) -> :rpc.async_call(node, CoopCache.TestClient, :get, [:key, :value, self]) end)
      end )
    |> List.flatten
    |> Enum.each(fn(key) -> :value = :rpc.yield(key) end)
    assert 1 == times_processed(:key, :value)
  end

  test "acquisition of state by newly started server" do
    # one: not running
    # two: no app
    # three: newcomer
    # four: running
    # five not running

    # this one the app started
    start_nodes([:four])
    # the one with no application running
    Flock.Server.start_nodes([:two], %{})
    assert :value == Flock.Server.rpc(:four, CoopCache.TestClient, :get, [:key, :value, self])
    assert  {nil, [key: :value]} == :rpc.call(:four@localhost, CoopCache.Server, :data, [:dist_cache])
    # this is the newcomer that should pick up the data from :two
    start_nodes([:three])
    assert :value == Flock.Server.rpc(:three, CoopCache.TestClient, :get, [:key, :value_ignored, self])
    assert 1 == times_processed(:key, :value)
    assert 0 == times_processed(:key, :value_ignored)
  end

  def times_processed(key, value) do
    times_processed(key, value, 0)
  end

  def times_processed(key, value, count) do
    case wait_for({:processed, ^key, ^value}, 200) do
      true ->
        times_processed(key, value, count + 1)
      false ->
        count
    end
  end

end
