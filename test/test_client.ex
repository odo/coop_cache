defmodule CoopCache.TestClient do
  import CoopCache

  def get(id, pid) do
    cached(:dist_cache, id) do
      send(pid, {:processed, id})
      :timer.sleep(10)
      id
    end
  end

end
