defmodule NexusMCP.Server.Tool do
  @moduledoc """
  Provides the `deftool` macro for declaring MCP tools alongside their handlers.
  """

  @doc """
  Defines a tool with its schema and handler in one place.

  ## Example

      deftool "get_page", "Get a page by ID",
        params: [id: {:string!, "Page ID"}] do
        page = CMS.get_page!(params["id"])
        {:ok, Map.take(page, [:id, :title, :slug])}
      end

  Inside the `do` block, `params` and `session` are bound.

  `deftool` works in a `NexusMCP.Server` module and in a `NexusMCP.Tools` module.

  ## Descriptions

  The tool description and param descriptions may be any expression that
  evaluates to a string at compile time, such as a module attribute, a function
  call, a heredoc, or `File.read!/1` together with `@external_resource`:

      @account_desc "Account ID (use list_accounts to find)"

      deftool "get_account", @account_desc,
        params: [account_id: {:string!, @account_desc}] do
        ...
      end

  A description that is not a string raises a `CompileError` at the `deftool`.

  ## Module defaults

  Params, `meta` and `annotations` given to `use NexusMCP.Tools` or
  `use NexusMCP.Server` apply to every tool in the module (see
  `NexusMCP.Tools`). Pass `skip_default_params: [:key, ...]` to leave default
  params out of one tool:

      deftool "list_accounts", "List accounts",
        params: [],
        skip_default_params: [:account_id] do
        ...
      end

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

  ## Meta

  Pass `meta` to attach server-side data to the tool definition, for example
  to mark tools for `c:NexusMCP.Server.tool_visible?/2`:

      deftool "delete_template", "Delete a template",
        params: [id: {:string!, "Template ID"}],
        meta: %{admin: true} do
        ...
      end

  `meta` is available as `tool.meta` in `tools/0` and `tool_visible?/2`, and is
  never sent to clients.
  """
  defmacro deftool(name, description, opts_or_params \\ [], do_block \\ []) do
    # Handle both `deftool "x", "y", params: [...] do ... end` (arity 4)
    # and `deftool "x", "y", params: [...], do: (...)` (arity 3)
    opts = Keyword.merge(opts_or_params, do_block)
    {block, opts} = Keyword.pop!(opts, :do)

    tool_opts = [
      params: Keyword.get(opts, :params, []),
      skip_default_params: Keyword.get(opts, :skip_default_params, []),
      annotations: Keyword.get(opts, :annotations),
      output_schema: Keyword.get(opts, :output_schema),
      meta: Keyword.get(opts, :meta)
    ]

    location = {__CALLER__.file, __CALLER__.line}

    # The definition is built by code evaluated in the module body, not here on
    # the syntax tree, so descriptions and params may be any expression: module
    # attributes, function calls, heredocs.
    #
    # Handlers are clauses of `__nexus_tool_call__/3`. The public
    # `__nexus_handle_tool_call__/3` is generated in `@before_compile`, so it
    # can add fallback clauses without splitting the deftool clauses.
    quote do
      @__nexus_tools__ NexusMCP.Server.Tool.__build__(
                         unquote(name),
                         unquote(description),
                         unquote(tool_opts),
                         Module.get_attribute(__MODULE__, :__nexus_tool_defaults__),
                         unquote(location)
                       )
      @__nexus_tool_sources__ {unquote(name), unquote(location), __MODULE__}

      @doc false
      def __nexus_tool_call__(unquote(name), var!(params), var!(session)) do
        _ = var!(params)
        _ = var!(session)
        unquote(block)
      end
    end
  end

  @doc false
  # Validates the tool defaults given to `use NexusMCP.Tools` or
  # `use NexusMCP.Server`. Evaluated in the module body.
  def __defaults__(opts, {file, line}) do
    params = Keyword.get(opts, :params, [])
    meta = Keyword.get(opts, :meta)
    annotations = Keyword.get(opts, :annotations)

    unless Keyword.keyword?(params) do
      compile_error!(file, line, "default params must be a keyword list, got: #{inspect(params)}")
    end

    unless is_nil(meta) or is_map(meta) do
      compile_error!(file, line, "default meta must be a map, got: #{inspect(meta)}")
    end

    unless is_nil(annotations) or is_map(annotations) do
      compile_error!(
        file,
        line,
        "default annotations must be a map, got: #{inspect(annotations)}"
      )
    end

    %{params: params, meta: meta, annotations: annotations}
  end

  @doc false
  # Builds a tool definition from the evaluated `deftool` arguments and the
  # module's defaults. Evaluated in the module body at compile time.
  def __build__(name, description, opts, defaults, {file, line}) do
    defaults = defaults || %{params: [], meta: nil, annotations: nil}

    unless is_binary(name) do
      compile_error!(file, line, "tool name must be a string, got: #{inspect(name)}")
    end

    unless is_binary(description) do
      compile_error!(
        file,
        line,
        "description of tool #{inspect(name)} must evaluate to a string, got: " <>
          inspect(description)
      )
    end

    params =
      merge_params(name, defaults.params, opts[:params], opts[:skip_default_params], file, line)

    schema =
      try do
        NexusMCP.Server.Schema.params_to_schema(params)
      rescue
        e in ArgumentError ->
          compile_error!(file, line, "tool #{inspect(name)}: " <> Exception.message(e))
      end

    %{name: name, description: description, inputSchema: schema}
    |> put_present(
      :annotations,
      merge_maps(defaults.annotations, opts[:annotations], &Map.merge/2)
    )
    |> put_present(:outputSchema, output_schema(name, opts[:output_schema]))
    |> put_present(:meta, merge_maps(defaults.meta, opts[:meta], &deep_merge/2))
  end

  # Default params come first, minus those the tool skips or redeclares. A
  # redeclared param takes the tool's position.
  defp merge_params(name, default_params, params, skip, file, line) do
    unless Keyword.keyword?(params) do
      compile_error!(
        file,
        line,
        "params of tool #{inspect(name)} must be a keyword list, got: #{inspect(params)}"
      )
    end

    case List.wrap(skip) -- Keyword.keys(default_params) do
      [] ->
        :ok

      unknown ->
        compile_error!(
          file,
          line,
          "tool #{inspect(name)} skips #{inspect(unknown)} in skip_default_params, " <>
            "but the module has no such default params"
        )
    end

    Keyword.drop(default_params, List.wrap(skip) ++ Keyword.keys(params)) ++ params
  end

  defp output_schema(_name, schema) when schema in [nil, false], do: nil

  defp output_schema(name, schema) do
    validate_output_schema!(name, schema)
    schema
  end

  defp merge_maps(nil, value, _fun), do: value
  defp merge_maps(default, value, _fun) when value in [nil, false], do: default
  defp merge_maps(default, value, fun), do: fun.(default, value)

  defp deep_merge(left, right) do
    Map.merge(left, right, fn
      _key, l, r when is_map(l) and is_map(r) and not is_struct(l) and not is_struct(r) ->
        deep_merge(l, r)

      _key, _l, r ->
        r
    end)
  end

  defp put_present(map, _key, value) when value in [nil, false], do: map
  defp put_present(map, key, value), do: Map.put(map, key, value)

  @doc false
  def compile_error!(file, line, description) do
    raise CompileError, file: file, line: line, description: description
  end

  @doc false
  # Raises when a name appears twice in `[{name, {file, line}, owner}]`,
  # pointing at the later declaration.
  def check_duplicates!(sources) do
    Enum.reduce(sources, %{}, fn {name, {file, line}, owner}, seen ->
      case seen do
        %{^name => {first_file, first_line, first_owner}} ->
          compile_error!(
            file,
            line,
            "tool #{inspect(name)} is declared more than once: in #{inspect(first_owner)} " <>
              "(#{Path.relative_to_cwd(first_file)}:#{first_line}) and in #{inspect(owner)}"
          )

        _ ->
          Map.put(seen, name, {file, line, owner})
      end
    end)

    :ok
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

  @doc false
  # The result an unknown tool name gets. Also returned for tools hidden from
  # the session by `tool_visible?/2`, so a hidden tool is indistinguishable
  # from one that does not exist.
  def unknown_tool(name), do: {:error, "Unknown tool: #{inspect(name)}"}

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
