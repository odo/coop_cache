CoopCache
=========

CoopCache (cooperative cache) is a specialized cache for Erlang/Elixir applications.

# Use case

* values are expensive to generate
* there is a finite and foreseeable number of items
* a value for a key is stable

# Properties

The main advantage of CoopCache is that every value is computed only once even when requested at a high frequency on a cold cache.

As values are written the cache grows until hitting a fized memory limit specified in Bytes. After that new values will not be cached and the computation will be more expensive due to an additional roundtrip to the server.

The memory limit is intended as a safety cap and should normally never be reached.

The cache_duration is the the number of seconds after the last activity (read or write) until coop_cache deletes a cache entry.

Please note that if computing a value results in an (errors, throws and exits) these errors are not cached.
That means that systems can recover, but it also means that potentially expensive computation until the error will be performed repeatedly.

# Usage

Mix configuration:

```elixir
config :coop_cache,
  nodes:  [],
  caches: [ {:example, %{ memory_limit: 50 * 1024 * 1024, cache_duration: 10 }} ]
```

caching:

```elixir
import CoopCache

cached(:example, :my_key) do
	some_expensive_operation()
end
```

CoopCache catches any errors/throws/exits and either returns `{:ok, result}` or `{:error, reason}`:

```elixir
iex(1)> import CoopCache
CoopCache
iex(2)> cached(:example, :my_key) do
...(2)>     :value
...(2)> end
{:ok, :value}
```

```elixir
iex(1)> import CoopCache
CoopCache
iex(2)> cached(:example, :my_key) do
...(2)>     throw(:kaputt)
...(2)> end

18:34:22.303 [error] Task #PID<0.176.0> started from #PID<0.175.0> terminating
** (stop) {:nocatch, :kaputt} [...]
{:error,
 {{:nocatch, :kaputt},
  [{:erl_eval, :do_apply, 6, [file: 'erl_eval.erl', line: 668]},
   {Wormhole.CallbackWrapper, :catch_errors, 2,
    [file: 'lib/wormhole/callback_wrapper.ex', line: 12]},
   {Task.Supervised, :do_apply, 2, [file: 'lib/task/supervised.ex', line: 85]},
   {Task.Supervised, :reply, 5, [file: 'lib/task/supervised.ex', line: 36]},
   {:proc_lib, :init_p_do_apply, 3, [file: 'proc_lib.erl', line: 247]}]}}
```

If you want to skip the cache you can return `{:nocache, value}`:

```elixir
iex(1)> import CoopCache
CoopCache
iex(2)> cached(:example, :my_key) do
...(2)>     {:nocache ,:off_the_record}
...(2)> end
{:ok, :off_the_record}
iex(3)> cached(:example, :my_key) do
...(3)>     :on_record
...(3)> end
{:ok, :on_record}
iex(4)> cached(:example, :my_key) do
...(4)>     :still_on_record
...(4)> end
{:ok, :on_record}
```

# Distribution

distribution can be enabled by adding nodes to the config:

```elixir
config :coop_cache,
  nodes:  [:"coop@fancyhost.com"],
  caches: [ {:example, %{ memory_limit: 50 * 1024 * 1024, cache_duration: 10 }} ]
```

When starting, coop_cache tries to connect the other nodes and then assumes that it runs the same sets of caches. At startup it copies over the current state of a random node on the cluster. Locks and writes are then distributed and coop_cache tries to do the computation for each key only once cluster-wide although this is not guaranteed.

# Tests

`make test`
