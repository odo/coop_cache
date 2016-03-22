defmodule CoopCache do
  use Application

  defmacro cached(name, key, do: block) do
    quote do
      name = unquote(name)
      key  = unquote(key)
      fun  = fn() ->
        unquote(block)
      end

      :ets.lookup(name, key)
      |> case do
        [] ->
          GenServer.call(name, {:write_or_wait, key, fun})
          |> case do
            {:error, :cache_full} -> fun.()
            value -> value
          end
        [{_, value}] ->
          GenServer.cast(name, {:activity, key})
          value
      end

    end
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
