use Mix.Config

config :coop_cache,
  nodes:  [:one@localhost, :two@localhost, :three@localhost, :four@localhost, :five@localhost],
  caches: [ {:dist_cache, %{ memory_limit: 1024 * 1024, callback_module: nil }} ]
