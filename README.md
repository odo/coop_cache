CoopCache
=========

cache hit
  read from ets (key) -> data

cache miss cold
  read from ets (key) -> empty
  call manager for write (key, fun) -> :wait_for_completion
  receive ({:cache_available, key})
  read from ets (key) -> data

    manager writes lock
    manager writes sender as subscribed
    manager spawns with fun
    handle_info({:cache_data_ready, data})
    write cache
    send ({:cache_available, key}) to all subscibers

cache in progress

  read from ets (key) -> empty
  call manager for write (key, fun) -> :wait_for_completion
    manager checks lock
    finds lock and subscribes sender
