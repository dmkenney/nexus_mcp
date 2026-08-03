# NexusMCP

MCP ([Model Context Protocol](https://modelcontextprotocol.io)) server library for Elixir.

Implements the **2025-11-25** spec over the Streamable HTTP transport, with a GenServer-per-session architecture and concurrent tool execution via `Task.Supervisor`.

Supports the three MCP server primitives:

- **Tools** — model-controlled functions (`deftool`)
- **Prompts** — user-controlled message templates (`defprompt`)
- **Resources** — application-controlled context (`defresource`, `defresource_template`)

## Installation

```elixir
def deps do
  [
    {:nexus_mcp, "~> 0.5.0"}
  ]
end
```

## Quick start

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

## Tools

Tools are exposed to MCP clients via `tools/list` and `tools/call`. Inside the `do` block, `params` and `session` are bound.

```elixir
deftool "get_page", "Get a page by ID",
  params: [id: {:string!, "Page ID"}] do
  page = CMS.get_page!(params["id"])
  {:ok, Map.take(page, [:id, :title, :slug, :body])}
end
```

Tool calls execute concurrently in supervised Task processes — slow tools don't block other RPCs on the same session.

### Param types

`:string`, `:integer`, `:number`, `:boolean`, `:object`, plus `{:array, type}`. Append `!` to mark required (`:string!`, `:integer!`, …). Pair with a description: `{:string!, "Page ID"}`.

### Annotations

Add MCP [tool annotations](https://modelcontextprotocol.io/specification/2025-11-25/server/tools#annotations) to hint behavior:

```elixir
deftool "delete_item", "Delete an item",
  params: [id: {:string!, "Item ID"}],
  annotations: %{readOnlyHint: false, destructiveHint: true, idempotentHint: true} do
  Items.delete!(params["id"])
  {:ok, %{deleted: true}}
end
```

Supported keys: `readOnlyHint`, `destructiveHint`, `idempotentHint`, `openWorldHint`, `title`.

### Output schemas

Add an [output schema](https://modelcontextprotocol.io/specification/2025-11-25/server/tools#output-schema) to describe the shape of a tool's result, so clients and models can rely on its structure instead of inferring it:

```elixir
deftool "get_weather", "Get current weather",
  params: [city: {:string!, "City name"}],
  output_schema: %{
    type: "object",
    properties: %{
      temperature: %{type: "number", description: "Temperature in celsius"},
      conditions: %{type: "string", description: "Weather conditions"}
    },
    required: ["temperature", "conditions"]
  } do
  {:ok, %{temperature: 22.5, conditions: "Partly cloudy"}}
end
```

The schema is advertised as `outputSchema` in `tools/list`. Tools that declare one also return their result in the `structuredContent` field of `tools/call`, alongside the serialized JSON in a text content block for backwards compatibility:

```json
{
  "content": [{ "type": "text", "text": "{\"temperature\":22.5,\"conditions\":\"Partly cloudy\"}" }],
  "structuredContent": { "temperature": 22.5, "conditions": "Partly cloudy" }
}
```

Your handler is unchanged — the same `{:ok, result}` populates both fields. Errors and pre-formatted content items never carry structured content.

Per the MCP specification, servers **MUST** provide structured results conforming to the declared schema. Two rules follow from that:

- **The root type must be `"object"`.** MCP 2025-11-25 restricts output schemas to objects, because `structuredContent` is itself typed as a JSON object. Declaring an array or scalar schema raises when the tool is defined. To return a list, wrap it: `%{type: "object", properties: %{entries: %{type: "array", ...}}}`.
- **A tool declaring a schema must return a map.** A list or scalar cannot conform, so it produces a tool execution error (`isError: true`) instead of a successful response silently missing the `structuredContent` it advertised.

`nexus_mcp` does not validate result *contents* against the schema — matching properties and types is a contract you are responsible for keeping.

## Prompts

Prompts are user-invoked templates (e.g. slash commands) surfaced via `prompts/list` and `prompts/get`. The handler returns a list of MCP messages.

```elixir
defprompt "code_review", "Ask the model to review code",
  arguments: [code: {:string!, "The code to review"}] do
  {:ok, [
    %{role: "user",
      content: %{type: "text", text: "Please review:\n" <> params["code"]}}
  ]}
end
```

Required arguments are validated before the handler runs — missing required args produce a `-32602` JSON-RPC error.

## Resources

Resources are application-controlled context surfaced via `resources/list`, `resources/templates/list`, and `resources/read`.

### Static resources

```elixir
defresource "config://app",
  name: "app_config",
  description: "Application configuration",
  mime_type: "application/json" do
  {:ok, Jason.encode!(MyApp.config())}
end
```

The handler can return:

- `{:ok, binary}` — wrapped as `text` if `mime_type` is textual (`text/*` or `application/json`), otherwise base64-encoded as `blob`
- `{:ok, %{text: string}}` or `{:ok, %{blob: base64}}` — passed through
- `{:error, :not_found}` — surfaces as JSON-RPC `-32002`

### Templated resources

Use RFC 6570 URI templates with `{var}` (single segment) or `{+var}` (multi-segment, reserved expansion):

```elixir
defresource_template "file:///{path}",
  name: "project_files",
  description: "Files in the project directory",
  mime_type: "text/plain" do
  {:ok, File.read!(params["path"])}
end

defresource_template "tree:///{+path}",
  name: "tree_node",
  mime_type: "application/json" do
  {:ok, Jason.encode!(Tree.fetch(params["path"]))}
end
```

URI captures land in `params` keyed by the template variable name.

### Subscriptions (not yet supported)

Per-resource subscriptions (`resources/subscribe`, `notifications/resources/updated`) are not implemented in this release. Resources are advertised with `"subscribe": false` at initialization.

## Per-session setup

Override `init/1` to validate or enrich the session at connection time, and `wrap_tool_call/2` to install process-local context (tenant ID, request span, etc.) before every tool runs:

```elixir
defmodule MyApp.MCP do
  use NexusMCP.Server, name: "my-app", version: "1.0.0"

  @impl true
  def init(session) do
    case authenticate(session.assigns[:api_key]) do
      {:ok, user} -> {:ok, put_in(session.assigns[:user], user)}
      :error      -> {:error, "unauthorized"}
    end
  end

  @impl true
  def wrap_tool_call(session, fun) do
    MyApp.Context.put_user_id(session.assigns[:user].id)
    fun.()
  rescue
    Ecto.NoResultsError -> {:error, "Not found"}
  end

  deftool "me", "Return the current user", params: [] do
    {:ok, %{id: session.assigns[:user].id}}
  end
end
```

## Transport options

```elixir
forward "/mcp", NexusMCP.Transport,
  server: MyApp.MCP,
  allowed_origins: ["https://myapp.com", "https://studio.myapp.com"]
```

When `allowed_origins` is set, requests with an `Origin` header not in the list are rejected with `403`. Requests without an `Origin` header are allowed (e.g. server-to-server).

## Session lifetime and memory

```elixir
defmodule MyApp.MCP do
  use NexusMCP.Server,
    name: "my-app",
    version: "1.0.0",
    hibernate_after: 60_000
end
```

`idle_timeout` (default `7_200_000`, 2 hours) is how long a session may sit
idle before it is terminated.

`hibernate_after` (default `60_000`) is how long a session must be quiet before
it hibernates. Hibernating collapses the heap the session grew while handling
requests, which the BEAM does not otherwise give back — with many concurrent
sessions holding large tool results, that heap dominates memory use.

It is debounced rather than applied per call: every request re-arms the timer,
so a session under steady traffic never hibernates and pays nothing, while one
that goes quiet releases its heap and re-grows on the next message. Hibernating
does not extend the inactivity deadline. Set `hibernate_after: :infinity` to
disable it.

## Distributed deployments

Session registry is swappable. Provide your own implementation of `NexusMCP.SessionRegistry` (e.g. backed by `:global`, `:pg`, or Horde) and configure it:

```elixir
config :nexus_mcp, registry: MyApp.DistributedRegistry
```

## Spec coverage

This release implements the **MCP 2025-11-25** server spec for:

- `initialize` + `notifications/initialized`
- `ping`
- `tools/list`, `tools/call` (with annotations, output schemas, and structured content)
- `prompts/list`, `prompts/get`
- `resources/list`, `resources/templates/list`, `resources/read`

Out of scope for this release (tracked separately):

- `resources/subscribe`, `resources/unsubscribe`, `notifications/resources/updated`
- `notifications/{prompts,resources}/list_changed`
- `completion/complete`
- Pagination cursors on `*/list` methods (whole list returned in one page)
- Full RFC 6570 URI template grammar (currently `{var}` and `{+var}`)

## License

MIT
