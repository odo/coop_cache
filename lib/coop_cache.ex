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

  def start(_type, _args) do
    caches     = Application.get_env(:coop_cache, :caches)
    supervisor = CoopCache.Supervisor.start_link
    Enum.each(
      caches,
      fn({name, options}) ->
        {:ok, _} = Supervisor.start_child(:coop_cache_sup, [name, options])
      end
    )
    supervisor
  end

end
