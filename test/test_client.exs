defmodule CoopCache.TestClient do
  import CoopCache

  def get(key, value, pid) do
    cached(:dist_cache, key) do
      send(pid, {:processed, key, value})
      :timer.sleep(10)
      value
    end
  end

end
