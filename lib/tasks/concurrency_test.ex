defmodule Mix.Tasks.ConcurrencyTest do
  use Mix.Task

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

  def run(_args) do
    Mix.Tasks.Run.run([])
    apps = [:coop_cache]
    node_count = 5
    config_file = "config/concurrency_test_config.exs"
    node_ids = Enum.to_list(1..node_count)
    node_names = Enum.map(node_ids, fn(id) -> node_name(id) end)
    full_node_names = Enum.map(node_ids, fn(id) -> full_node_name(id) end)
    Enum.each( node_names, fn(name) -> start_node(name, config_file, apps) end )
    call_keys = Enum.map(
      full_node_names,
      fn(full_node_name) ->
        :timer.sleep(1)
        Enum.map(1..5, fn(_) -> :rpc.async_call(full_node_name, __MODULE__, :get, [20, self]) end)
      end
    )
    Enum.each(List.flatten(call_keys), fn(key) -> 20 = :rpc.yield(key) end)
    1 = times_processed(1)
  end

  def times_processed(id) do
    times_processed(id, 0)
  end

  def times_processed(id, count) do
    case wait_for({:processed, id}, 200) do
      true ->
        times_processed(id, count + 1)
      false ->
        count
    end
  end

  def start_node(name, config_file, apps) do
    {:ok, full_name} = :slave.start(:localhost, name)
    Enum.each(
      :code.get_path,
      fn(path) -> true = :rpc.call(full_name, :code, :add_path, [path]) end
    )
    {:ok, _} = :rpc.call(full_name, :application, :ensure_all_started, [:elixir])
    :rpc.call(full_name, Code, :require_file, ["mix.exs"])
    configs = :rpc.call(full_name, Mix.Config, :read!, [config_file])
    Enum.each(
      configs,
      fn({app, config}) ->
        Enum.each(
          config,
          fn({key, value}) ->
            :ok = :rpc.call(full_name, :application, :set_env, [app, key, value])
          end
        )
      end
    )
    Enum.each(
      apps,
      fn(app) ->
        IO.puts("#{full_name}: starting app #{app}")
        {:ok, _} = :rpc.call(full_name, :application, :ensure_all_started, [app])
      end
    )
  end

  def node_name(id) do
    String.to_atom("coop_test_" <> Integer.to_string(id))
  end

  def full_node_name(id) do
    String.to_atom("coop_test_" <> Integer.to_string(id) <> "@localhost")
  end

  def get(id, pid) do
    cached(:dist_cache, id) do
      send(pid, {:processed, id})
      :timer.sleep(10)
      id
    end
  end

end
