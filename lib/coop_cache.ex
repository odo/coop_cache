defmodule CoopCache do
  use Application

  defmacro cached(name, key, do: block) do
    quote do
      name = unquote(name)
      key  = unquote(key)
      fun  = fn() ->
        unquote(block)
      end


      case :ets.lookup(name, key) do
        [] ->
          case GenServer.call(name, {:write_or_wait, key, fun}, :infinity) do
            {:ok, value}            -> {:ok, value}
            {:error, :cache_full}   -> Wormhole.capture(fun, [crush_report: true, timeout_ms: :infinity]) |> strip_nocache
            {:error, error_message} -> {:error, error_message}
          end
        [{_, value}] ->
          GenServer.cast(name, {:activity, key})
          {:ok, value}
      end

    end
  end

  def strip_nocache({:ok, {:nocache, value}}) do
    {:ok, value}
  end
  def strip_nocache(reply) do
    reply
  end

  def start(_type, _args) do
    supervisor = CoopCache.Supervisor.start_link
    Application.get_env(:coop_cache, :caches)
    |> Enum.each(&start_child/1)
    supervisor
  end

  def start_child({name, options}) do
    {:ok, _} = Supervisor.start_child(:coop_cache_sup, [name, options])
  end
end
