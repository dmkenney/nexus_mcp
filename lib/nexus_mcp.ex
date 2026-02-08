defmodule NexusMCP do
  @moduledoc """
  MCP (Model Context Protocol) server library for Elixir.

  NexusMCP implements the MCP Streamable HTTP transport specification with a
  GenServer-per-session architecture. Each MCP client gets its own process,
  tool calls execute concurrently, and SSE connections are monitored.

  ## Usage

  Define your server with `use NexusMCP.Server` and declare tools with `deftool`:

      defmodule MyApp.MCP do
        use NexusMCP.Server,
          name: "my-app",
          version: "1.0.0"

        deftool "hello", "Say hello",
          params: [name: {:string!, "Person's name"}] do
          {:ok, "Hello, \#{params["name"]}!"}
        end
      end

  Add the supervisor to your application:

      children = [
        {NexusMCP.Supervisor, []},
        # ...
      ]

  Route requests to the transport:

      forward "/mcp", NexusMCP.Transport, server: MyApp.MCP

  See `NexusMCP.Server` for the full behaviour reference and `NexusMCP.Server.Tool`
  for the `deftool` macro and param type DSL.
  """
end
