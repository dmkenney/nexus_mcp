# NexusMCP

MCP (Model Context Protocol) server library for Elixir with per-session GenServer architecture and Streamable HTTP transport.

## Installation

Add `nexus_mcp` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:nexus_mcp, "~> 0.2.0"}
  ]
end
```

## Usage

### Define your MCP server

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

### Tool annotations

You can add [MCP tool annotations](https://modelcontextprotocol.io/specification/2025-06-18/server/tools#annotations) to provide hints about a tool's behavior:

```elixir
deftool "list_items", "List all items",
  params: [],
  annotations: %{readOnlyHint: true, destructiveHint: false} do
  {:ok, Items.list_all()}
end

deftool "delete_item", "Delete an item",
  params: [id: {:string!, "Item ID"}],
  annotations: %{readOnlyHint: false, destructiveHint: true, idempotentHint: true} do
  Items.delete!(params["id"])
  {:ok, %{deleted: true}}
end
```

Supported annotation keys: `readOnlyHint`, `destructiveHint`, `idempotentHint`, `openWorldHint`, `title`.

### Add the supervisor to your application

```elixir
children = [
  {NexusMCP.Supervisor, []},
  # ...
]
```

### Route requests to the transport

```elixir
forward "/mcp", NexusMCP.Transport, server: MyApp.MCP
```

### Origin validation

Restrict which origins can connect by passing `allowed_origins`:

```elixir
forward "/mcp", NexusMCP.Transport,
  server: MyApp.MCP,
  allowed_origins: ["https://myapp.com", "https://studio.myapp.com"]
```

When set, requests with an `Origin` header not in the list are rejected with `403 Forbidden`. Requests without an `Origin` header are allowed (e.g. server-to-server calls).

## License

MIT
