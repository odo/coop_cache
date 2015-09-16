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
        Enum.map(1..5, fn(_) -> :rpc.async_call(node, CoopCache.TestClient, :get, [:test_msg, self]) end)
      end )
    |> List.flatten
    |> Enum.each(fn(key) -> :test_msg = :rpc.yield(key) end)
    assert 1 == times_processed(:test_msg)
  end

  def times_processed(id) do
    times_processed(id, 0)
  end

  def times_processed(id, count) do
    case wait_for({:processed, ^id}, 200) do
      true ->
        times_processed(id, count + 1)
      false ->
        count
    end
  end

end
