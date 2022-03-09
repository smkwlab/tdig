defmodule Tdig.MixProject do
  use Mix.Project

  def project do
    [
      app: :tdig,
      escript: escript_config(),
      version: "0.1.1",
      name: "Tdig",
      elixir: "~> 1.12",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:tenbin_dns, git: "https://github.com/toshi0806/tenbin_dns.git", tag: "0.3.0"},
      {:socket, "~> 0.3.13"},
      {:zoneinfo, "~> 0.1.0"},
    ]
  end

  defp escript_config do
    [
      main_module: Tdig.CLI
    ]
  end
end
