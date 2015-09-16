CoopCache
=========

CoopCache (cooperative cache) is a specialized cache for Erlang/Elixir applications.

# Use case

* values are expensive to generate
* there is a finite and foreseeable number of items
* you don't need to invalidate single values
* your source has a version (an arbitrary term)

# Properties

The main advantage of CoopCache is that every value is computed only once even when requested at a high frequency on a cold cache.

As values are written the cache grows until hitting a fized memory limit. After that new values will not be cached and the computation will be more expensive due to an additional roundtrip to the server.

The memory limit is intended as a safety cap and should normally never be reached.

The cache can be reset as a whole. Resetting happens when your source gets a new version and the old version becomes invalid. This will also handle the in flight computation of values so from the outside every reply after the reset will have been computed after the reset even if the request was send before.

Resets will be broadcasted to all caches in the cluster to trigger their update in turn. If one cache is told to reset it calls the callback_module.reset/1 is called with the desired version.

# Usage

Mix configuration:

```elixir
config :coop_cache,
  nodes:  [],
  caches: [ {:example, %{ memory_limit: 1024 * 1024, version: nil, callback_module: nil }} ]
```

caching:

```elixir
import CoopCache

cached(:example, :my_key) do
	some_expensive_operation()
end
```

resetting:

```elixir
CoopCache.Server.reset(:example)
```

# Distribution

distribution can be anabled by adding nodes to the config:


```elixir
config :coop_cache,
  nodes:  [:"coop@fancyhost.com"],
  caches: [ {:example, %{ memory_limit: 1024 * 1024 }} ]
```

When starting coop_cache tries to connect the other nodes and then assumes that it runs the same sets of caches. Locks and writes are then distributed and coop_cache tries to do the computation for each key only once cluster-wide although this is not guaranteed.

Please note that the cache only accepts writes from other caches with the same version. The version starts with 1 and is then incremented during each reset.  

# Tests
`./deps/flock/run_test`