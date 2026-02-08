defmodule NexusMCP.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :nexus_mcp,
      version: @version,
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      name: "NexusMCP",
      description:
        "MCP (Model Context Protocol) server library for Elixir with per-session GenServer architecture",
      package: package(),
      source_url: "https://github.com/brightsite/nexus_mcp"
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:plug, "~> 1.14"},
      {:jason, "~> 1.4"},
      {:plug_cowboy, "~> 2.5", only: :test},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp docs do
    [
      main: "NexusMCP",
      extras: ["README.md"],
      groups_for_modules: [
        "Server DSL": [
          NexusMCP.Server,
          NexusMCP.Server.Tool,
          NexusMCP.Server.Schema
        ],
        Infrastructure: [
          NexusMCP.Transport,
          NexusMCP.Supervisor,
          NexusMCP.SessionRegistry
        ],
        Internal: [
          NexusMCP.Session,
          NexusMCP.SSE,
          NexusMCP.JsonRpc,
          NexusMCP.SessionRegistry.Local
        ]
      ]
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      files: ~w(lib .formatter.exs mix.exs README* LICENSE*),
      links: %{"GitHub" => "https://github.com/brightsite/nexus_mcp"}
    ]
  end
end
