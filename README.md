# NexusMCP

MCP (Model Context Protocol) server library for Elixir with per-session GenServer architecture.

## Installation

Add `nexus_mcp` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:nexus_mcp, "~> 0.1.0"}
  ]
end
```

## Usage

Define your MCP server:

```elixir
defmodule MyApp.MCP do
  use NexusMCP.Server,
    name: "my-app",
    version: "1.0.0"

  deftool "hello", "Say hello",
    params: [name: {:string!, "Person's name"}] do
    {:ok, "Hello, #{params["name"]}!"}
  end
end
```

Add the supervisor to your application:

```elixir
children = [
  {NexusMCP.Supervisor, []},
  # ...
]
```

Route requests to the transport:

```elixir
forward "/mcp", NexusMCP.Transport, server: MyApp.MCP
```

## License

MIT
