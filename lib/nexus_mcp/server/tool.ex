defmodule NexusMCP.Server.Tool do
  @moduledoc """
  Provides the `deftool` macro and `@before_compile` hook for accumulating
  tool definitions alongside their handlers.
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
  """
  defmacro deftool(name, description, opts_or_params \\ [], do_block \\ []) do
    # Handle both `deftool "x", "y", params: [...] do ... end` (arity 4)
    # and `deftool "x", "y", params: [...], do: (...)` (arity 3)
    opts = Keyword.merge(opts_or_params, do_block)
    {block, opts} = Keyword.pop!(opts, :do)
    params_def = Keyword.get(opts, :params, [])

    schema = Schema.params_to_schema(params_def)

    tool_def = %{
      name: name,
      description: description,
      inputSchema: schema
    }

    quote do
      @__nexus_tools__ unquote(Macro.escape(tool_def))

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

  @doc false
  defmacro __before_compile__(env) do
    tools = Module.get_attribute(env.module, :__nexus_tools__) || []
    has_manual_tools = Module.defines?(env.module, {:tools, 0})
    has_manual_handle = Module.defines?(env.module, {:handle_tool_call, 3})

    cond do
      tools != [] and has_manual_tools ->
        raise CompileError,
          file: env.file,
          line: 0,
          description:
            "#{inspect(env.module)} defines both deftool and a manual tools/0. " <>
              "Use one or the other."

      tools != [] ->
        # Reverse because @accumulate prepends
        tools = Enum.reverse(tools)

        quote do
          @impl NexusMCP.Server
          def tools, do: unquote(Macro.escape(tools))

          unless unquote(has_manual_handle) do
            @impl NexusMCP.Server
            def handle_tool_call(name, params, session) do
              __nexus_handle_tool_call__(name, params, session)
            end
          end
        end

      true ->
        # No deftool macros used — don't generate anything
        nil
    end
  end
end
