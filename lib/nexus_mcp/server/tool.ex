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
  is unchanged — the same `{:ok, result}` is used for both fields.

  Per the MCP specification, servers MUST provide structured results that conform
  to the declared schema. Two consequences follow:

    * The schema's root type must be `"object"` — the spec restricts output
      schemas to objects, so anything else raises when the tool is defined.
    * A tool declaring a schema must return a map. Anything else — a list, a
      scalar, or pre-formatted content blocks — cannot conform, so it becomes a
      tool execution error (`isError: true`) rather than a successful response
      missing the promised `structuredContent`. Unstructured content may
      accompany a structured result, but cannot replace it; a tool that needs to
      return content blocks directly should omit `output_schema`.

  `nexus_mcp` does not validate result *contents* against the schema — matching
  properties and types remains a contract you are responsible for keeping.
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

                         if output_schema do
                           NexusMCP.Server.Tool.validate_output_schema!(
                             unquote(name),
                             output_schema
                           )

                           Map.put(td, :outputSchema, output_schema)
                         else
                           td
                         end
                       end)

      def __nexus_handle_tool_call__(unquote(name), var!(params), var!(session)) do
        _ = var!(params)
        _ = var!(session)
        unquote(block)
      end
    end
  end

  @doc """
  Raises unless `schema` is a valid MCP output schema.

  MCP 2025-11-25 restricts `outputSchema` to `type: "object"` at the root, since
  `structuredContent` is typed as a JSON object. Advertising an array or scalar
  schema would promise clients a result shape the protocol cannot carry, so it is
  rejected when the tool is defined rather than when it is first called.
  """
  @spec validate_output_schema!(String.t(), map()) :: :ok
  def validate_output_schema!(tool_name, schema) when is_map(schema) do
    case schema[:type] || schema["type"] do
      "object" ->
        :ok

      other ->
        raise ArgumentError,
              "tool #{inspect(tool_name)} declares an output_schema with root type " <>
                "#{inspect(other)}. MCP 2025-11-25 restricts output schemas to " <>
                ~s(type: "object" at the root — wrap the value in an object, e.g. ) <>
                ~s(%{type: "object", properties: %{items: #{inspect(schema)}}}.)
    end
  end

  def validate_output_schema!(tool_name, schema) do
    raise ArgumentError,
          "tool #{inspect(tool_name)} declares an output_schema that is not a map: " <>
            inspect(schema)
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
