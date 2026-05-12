defmodule NexusMCP.Server.Resource do
  @moduledoc """
  Provides `defresource` and `defresource_template` macros for declaring
  MCP resources alongside their read handlers.

  Resources are application-controlled context surfaced to MCP clients via
  `resources/list`, `resources/templates/list`, and `resources/read`
  (MCP spec 2025-11-25).

  ## Static resources

      defresource "config://app",
        name: "app_config",
        description: "Application configuration",
        mime_type: "application/json" do
        {:ok, Jason.encode!(MyApp.config())}
      end

  ## Templated resources

      defresource_template "file:///{path}",
        name: "project_files",
        description: "Files in the project directory",
        mime_type: "text/plain" do
        {:ok, File.read!(params["path"])}
      end

  URI template syntax supports two RFC 6570 operators:

  - `{var}` — matches a single path segment (no `/`)
  - `{+var}` — matches one or more segments (reserved expansion)

  Inside the `do` block, `params` (URI captures) and `session` are bound.

  ## Return shape

  The handler returns one of:

  - `{:ok, binary}` — wrapped as `text` if `mime_type` is textual
    (`text/*` or `application/json`), otherwise base64-encoded as `blob`
  - `{:ok, %{text: string}}` or `{:ok, %{blob: base64}}` — passed through
  - `{:error, reason}` — surfaces as JSON-RPC `-32002` resource-not-found
  """

  @doc """
  Defines a static resource and its read handler.
  """
  defmacro defresource(uri, opts, do_block \\ []) do
    opts = Keyword.merge(opts, do_block)
    {block, opts} = Keyword.pop!(opts, :do)

    name = Keyword.fetch!(opts, :name)
    description = Keyword.get(opts, :description)
    mime_type = Keyword.get(opts, :mime_type)

    resource_def =
      %{uri: uri, name: name}
      |> maybe_put(:description, description)
      |> maybe_put(:mimeType, mime_type)

    quote do
      @__nexus_resources__ unquote(Macro.escape(resource_def))

      def __nexus_handle_resource_read__(unquote(uri), var!(params), var!(session)) do
        _ = var!(params)
        _ = var!(session)
        unquote(block)
      end
    end
  end

  @doc """
  Defines a templated resource and its read handler.
  """
  defmacro defresource_template(uri_template, opts, do_block \\ []) do
    opts = Keyword.merge(opts, do_block)
    {block, opts} = Keyword.pop!(opts, :do)

    name = Keyword.fetch!(opts, :name)
    description = Keyword.get(opts, :description)
    mime_type = Keyword.get(opts, :mime_type)

    {regex_source, var_names} = compile_template(uri_template)

    template_def =
      %{
        uriTemplate: uri_template,
        name: name,
        __regex__: regex_source,
        __vars__: var_names
      }
      |> maybe_put(:description, description)
      |> maybe_put(:mimeType, mime_type)

    quote do
      @__nexus_resource_templates__ unquote(Macro.escape(template_def))

      def __nexus_handle_resource_read_template__(
            unquote(uri_template),
            var!(params),
            var!(session)
          ) do
        _ = var!(params)
        _ = var!(session)
        unquote(block)
      end
    end
  end

  @doc """
  Strips the internal `__regex__` / `__vars__` fields from a template definition
  before serializing it over the wire.
  """
  def public_template(%{} = template) do
    Map.drop(template, [:__regex__, :__vars__])
  end

  @doc """
  Try to match a URI against a list of compiled templates.

  Returns `{:ok, template, params}` on the first match, or `:error`.
  """
  def match_template(uri, templates) when is_binary(uri) and is_list(templates) do
    Enum.find_value(templates, :error, fn template ->
      {:ok, regex} = Regex.compile(template.__regex__)

      case Regex.named_captures(regex, uri) do
        nil -> nil
        captures -> {:ok, template, captures}
      end
    end)
  end

  @doc """
  Compile an RFC 6570 URI template (subset: `{var}` and `{+var}`) to a regex
  source string plus the list of variable names.

  ## Examples

      iex> NexusMCP.Server.Resource.compile_template("file:///{path}")
      {"^file:///(?<path>[^/]+)$", ["path"]}

      iex> NexusMCP.Server.Resource.compile_template("file:///{+path}")
      {"^file:///(?<path>.+)$", ["path"]}
  """
  def compile_template(uri_template) when is_binary(uri_template) do
    {regex_parts, vars} =
      uri_template
      |> tokenize()
      |> Enum.map_reduce([], fn
        {:literal, text}, vars ->
          {Regex.escape(text), vars}

        {:var, name}, vars ->
          {"(?<#{name}>[^/]+)", [name | vars]}

        {:reserved, name}, vars ->
          {"(?<#{name}>.+)", [name | vars]}
      end)

    {"^" <> IO.iodata_to_binary(regex_parts) <> "$", Enum.reverse(vars)}
  end

  defp tokenize(template), do: tokenize(template, [])

  defp tokenize("", acc), do: Enum.reverse(acc)

  defp tokenize(rest, acc) do
    case :binary.match(rest, "{") do
      :nomatch ->
        tokenize("", [{:literal, rest} | acc])

      {start, _} ->
        literal = binary_part(rest, 0, start)
        after_brace = binary_part(rest, start + 1, byte_size(rest) - start - 1)

        case :binary.match(after_brace, "}") do
          :nomatch ->
            raise ArgumentError, "Unterminated URI template variable in #{inspect(rest)}"

          {close, _} ->
            expr = binary_part(after_brace, 0, close)
            after_close = binary_part(after_brace, close + 1, byte_size(after_brace) - close - 1)

            token =
              case expr do
                "+" <> name -> {:reserved, name}
                name -> {:var, name}
              end

            acc =
              if literal == "" do
                [token | acc]
              else
                [token, {:literal, literal} | acc]
              end

            tokenize(after_close, acc)
        end
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
