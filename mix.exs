defmodule Tdig.MixProject do
  use Mix.Project

  @app :tdig

  def project do
    [
      app: :tdig,
      version: "0.3.0",
      name: "Tdig",
      elixir: "~> 1.12",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: [{@app, release()}],
      preferred_cli_env: [release: :prod]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Tdig.CLI, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:bakeware, "~> 0.2.3", runtime: false},
      {:tenbin_dns, git: "https://github.com/smkwlab/tenbin_dns.git", tag: "0.3.4"},
      {:socket, "~> 0.3.13"},
      {:zoneinfo, "~> 0.1.0"},
    ]
  end

  defp release do
    [
      overwrite: true,
      cookie: "#{@app}_cookie",
      quiet: true,
      steps: [:assemble, &Bakeware.assemble/1],
      strip_beams: Mix.env() == :prod
    ]
  end
end
