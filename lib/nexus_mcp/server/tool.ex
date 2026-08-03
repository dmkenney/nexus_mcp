defmodule NexusMCP.Server.Tool do
  @moduledoc """
  Provides the `deftool` macro for declaring MCP tools alongside their handlers.
  """

  alias NexusMCP.Server.Schema

  @doc """
  Defines a tool with its schema and handler in one place.

  ## Example

      deftool "get_page", "Get a page by ID",
        params: [id: {:string!, "Page ID"}] do
        page = CMS.get_page!(params["id"])
        {:ok, Map.take(page, [:id, :title, :slug])}
      end

  Inside the `do` block, `params` and `session` are bound.

  ## Annotations

  Pass `annotations` to provide hints about the tool's behavior to MCP clients:

      deftool "delete_item", "Delete an item",
        params: [id: {:string!, "Item ID"}],
        annotations: %{readOnlyHint: false, destructiveHint: true, idempotentHint: true} do
        Items.delete!(params["id"])
        {:ok, %{deleted: true}}
      end

  Supported keys: `readOnlyHint`, `destructiveHint`, `idempotentHint`, `openWorldHint`, `title`.

  ## Output schema

  Pass `output_schema` with a JSON Schema describing the shape of the tool's
  result. It is advertised to clients as `outputSchema` in `tools/list`. MCP
  2025-11-25 restricts it to `type: "object"` at the root:

      deftool "get_weather", "Get current weather",
        params: [city: {:string!, "City name"}],
        output_schema: %{
          type: "object",
          properties: %{
            temperature: %{type: "number"},
            conditions: %{type: "string"}
          },
          required: ["temperature", "conditions"]
        } do
        {:ok, %{temperature: 22.5, conditions: "Partly cloudy"}}
      end

  When a tool declares an output schema, successful map results are also returned
  in the `structuredContent` field of `tools/call`, alongside the serialized JSON
  in a text content block for backwards compatibility. The handler's return value
  is unchanged — the same `{:ok, result}` is used for both fields. Because the
  spec types `structuredContent` as an object, non-map results (lists, scalars)
  are returned as text content only.

  Per the MCP specification, servers MUST provide structured results that conform
  to the declared schema; `nexus_mcp` does not validate results against it.
  """
  defmacro deftool(name, description, opts_or_params \\ [], do_block \\ []) do
    # Handle both `deftool "x", "y", params: [...] do ... end` (arity 4)
    # and `deftool "x", "y", params: [...], do: (...)` (arity 3)
    opts = Keyword.merge(opts_or_params, do_block)
    {block, opts} = Keyword.pop!(opts, :do)
    params_def = Keyword.get(opts, :params, [])
    annotations_def = Keyword.get(opts, :annotations, nil)
    output_schema_def = Keyword.get(opts, :output_schema, nil)

    schema = Schema.params_to_schema(params_def)

    tool_def = %{
      name: name,
      description: description,
      inputSchema: schema
    }

    quote do
      @__nexus_tools__ unquote(Macro.escape(tool_def))
                       |> then(fn td ->
                         annotations = unquote(annotations_def)
                         if annotations, do: Map.put(td, :annotations, annotations), else: td
                       end)
                       |> then(fn td ->
                         output_schema = unquote(output_schema_def)
                         if output_schema, do: Map.put(td, :outputSchema, output_schema), else: td
                       end)

      def __nexus_handle_tool_call__(unquote(name), var!(params), var!(session)) do
        _ = var!(params)
        _ = var!(session)
        unquote(block)
      end
    end
  end

  @doc """
  Formats Ecto changeset errors into a human-readable error tuple.
  """
  def format_changeset_errors(%{errors: errors}) do
    messages =
      Enum.map(errors, fn {field, {msg, opts}} ->
        msg =
          Enum.reduce(opts, msg, fn {key, val}, acc ->
            String.replace(acc, "%{#{key}}", to_string(val))
          end)

        "#{field}: #{msg}"
      end)

    {:error, Enum.join(messages, ", ")}
  end
end
