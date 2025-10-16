defmodule CoopCache.Mixfile do
  use Mix.Project

  def project do
    [
      app: :coop_cache,
      version: "2.1.0",
      elixir: "~> 1.5",
      description: description(),
      package: package(),
      build_embedded: Mix.env == :prod,
      start_permanent: Mix.env == :prod,
      deps: deps()
    ]
  end

  # Configuration for the OTP application
  #
  # Type `mix help compile.app` for more information
  def application do
    [
        mod: {CoopCache, []}
    ]
  end


  # Dependencies can be Hex packages:
  #
  #   {:mydep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:mydep, git: "https://github.com/elixir-lang/mydep.git", tag: "0.1.0"}
  #
  # Type `mix help deps` for more examples and options
  defp deps() do
    [
      {:flock, [git: "https://github.com/odo/flock.git", only: :test]},
      {:wormhole, [git: "https://github.com/renderedtext/wormhole.git", branch: "master"]}
    ]
  end

  defp description() do
    "CoopCache (cooperative cache) is a specialized cache for Erlang/Elixir applications."
  end

  defp package() do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/odo/coop_cache"}
    ]
  end
end
