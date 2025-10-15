defmodule CoopCache.Supervisor do

  def start_link do
    DynamicSupervisor.start_link(name: __MODULE__)
  end

  def start_child({name, options}) do
    child = %{
      id: CoopCache.Server,
      type: :worker,
      start: {CoopCache.Server, :start_link, [name, options]},
      restart: :permanent
    }
    DynamicSupervisor.start_child(__MODULE__, child)
  end


end
