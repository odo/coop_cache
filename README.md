CoopCache
=========

CoopCache (cooperative cache) is a specialized cache for Erlang/Elixir applications.

# Use case

* values are expensive to generate
* there is a finite and foreseeable number of items
* you don't need to invalidate single values

# Properties

The main advantage of CoopCache is that every value is computed only once even when requested at a high frequency on a cold cache.

As values are written the cache grows until hitting a fized memory limit. After that new values will not be cached and the computation will be more expensive due to an additional roundtrip to the server. 
 
The memory limit is intended as a safety cap and should normally never be reached.

The cache can be reset as a whole. This will also handle the in flight computation of values so from the outside every reply after the reset will have been computed after the reset even if the request was send before.

# Usage

Mix configuration:

```elixir
config :coop_cache,
	caches: [ {:test_cache, %{ memory_limit: 1024 * 1024 }} ]
```

caching:

```elixir
import CoopCache

cached(:test_cache, :my_key) do
	some_expensive_operation()
end
```

resetting:

```elixir
CoopCache.Server.reset(:test_cache)
```
 