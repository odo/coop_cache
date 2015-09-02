defmodule CoopCache.Supervisor do
  import Supervisor.Spec

  def start_link do
    children       = [ worker(CoopCache.Server, [], restart: :permanent) ]
    Supervisor.start_link(children, name: :coop_cache_sup, strategy: :simple_one_for_one)
  end

end
