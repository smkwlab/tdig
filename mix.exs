defmodule Tdig.MixProject do
  use Mix.Project

  @app :tdig

  def project do
    [
      app: :tdig,
      version: "0.3.0",
      name: "Tdig",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: [{@app, release()}],
      escript: escript(),
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
        flags: [:error_handling, :underspecs],
        ignore_warnings: ".dialyzer_ignore.exs"
      ]
    ]
  end

  def cli do
    [preferred_envs: [release: :prod]]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    case Mix.env() do
      :prod ->
        [
          extra_applications: [:logger],
          mod: {Tdig.CLI, []}
        ]
      _ ->
        [extra_applications: [:logger]]
    end
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:bakeware, "~> 0.2.3", runtime: false},
      {:tenbin_dns, git: "https://github.com/smkwlab/tenbin_dns.git", tag: "0.7.0"},
      {:socket, "~> 0.3.13"},
      {:zoneinfo, "~> 0.1.0"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
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

  defp escript do
    [
      main_module: Tdig.CLI,
      name: "tdig"
    ]
  end
end
