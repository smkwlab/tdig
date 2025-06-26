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
      releases: releases(),
      preferred_cli_env: [release: :prod],
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
        flags: [:error_handling, :underspecs],
        ignore_warnings: ".dialyzer_ignore.exs"
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {Tdig.Application, []},
      extra_applications: [:logger, :burrito]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:burrito, "~> 1.3"},
      {:tenbin_dns, git: "https://github.com/smkwlab/tenbin_dns.git", tag: "0.5.4"},
      {:socket, "~> 0.3.13"},
      {:zoneinfo, "~> 0.1.0"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
    ]
  end

  defp releases do
    [
      tdig: [
        overwrite: true,
        cookie: "#{@app}_cookie",
        quiet: true,
        steps: [:assemble, &Burrito.wrap/1],
        strip_beams: Mix.env() == :prod,
        burrito: [
          targets: [
            macos: [
              os: :darwin, 
              cpu: :aarch64,
              custom_erts: "../otp/otp_27.3.4.1_darwin_aarch64_custom.tar.gz"
            ]
          ]
        ]
      ]
    ]
  end
end
