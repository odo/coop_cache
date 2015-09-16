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

  test "cooperation" do
    nodes =
    Flock.Server.start_nodes(
      [:one, :two, :three, :four, :five],
      %{config: "config/concurrency_test_config.exs",
        apps: [:coop_cache]}
    )
    Enum.each(nodes, fn(node) -> :rpc.call(node, Code, :eval_file, ["test/test_client.ex"]) end)
    call_keys = Enum.map(
      nodes,
      fn(node) ->
        :timer.sleep(1)
        Enum.map(1..5, fn(_) -> :rpc.async_call(node, CoopCache.TestClient, :get, [:test_msg, self]) end)
      end
    )
    Enum.each(List.flatten(call_keys), fn(key) -> :test_msg = :rpc.yield(key) end)
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
