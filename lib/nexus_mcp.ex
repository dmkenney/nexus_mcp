defmodule NexusMCP do
  @moduledoc """
  MCP ([Model Context Protocol](https://modelcontextprotocol.io)) server library for Elixir.

  Implements the **2025-11-25** spec over the Streamable HTTP transport, with a
  GenServer-per-session architecture. Each client gets its own process, tool
  calls execute concurrently in supervised Tasks, and SSE connections are
  monitored for cleanup.

  Supports all three MCP server primitives:

  - **Tools** — model-controlled functions (`NexusMCP.Server.Tool.deftool/4`)
  - **Prompts** — user-controlled message templates (`NexusMCP.Server.Prompt.defprompt/4`)
  - **Resources** — application-controlled context
    (`NexusMCP.Server.Resource.defresource/3`,
    `NexusMCP.Server.Resource.defresource_template/3`)

  ## Quick start

      defmodule MyApp.MCP do
        use NexusMCP.Server,
          name: "my-app",
          version: "1.0.0"

        deftool "hello", "Say hello",
          params: [name: {:string!, "Person's name"}] do
          {:ok, "Hello, \#{params["name"]}!"}
        end

        defprompt "greet", "Greet someone formally",
          arguments: [name: {:string!, "Name"}] do
          {:ok, [%{role: "user",
                   content: %{type: "text",
                              text: "Compose a formal greeting for " <> params["name"]}}]}
        end

        defresource "config://app",
          name: "app_config",
          mime_type: "application/json" do
          {:ok, Jason.encode!(MyApp.config())}
        end
      end

  Add the supervisor to your application:

      children = [
        {NexusMCP.Supervisor, []},
        # ...
      ]

  Route requests to the transport:

      forward "/mcp", NexusMCP.Transport, server: MyApp.MCP

  See `NexusMCP.Server` for the full behaviour reference.

  ## Spec coverage

  This release implements the **MCP 2025-11-25** server spec for:

  - `initialize` + `notifications/initialized`
  - `ping`
  - `tools/list`, `tools/call` (with annotations)
  - `prompts/list`, `prompts/get`
  - `resources/list`, `resources/templates/list`, `resources/read`

  Not yet implemented: resource subscriptions, list_changed notifications,
  `completion/complete`, and pagination cursors. The library advertises
  `subscribe: false` and `listChanged: false` for the relevant capabilities.
  """
end
