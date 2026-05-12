defmodule NexusMCP.Server.Prompt do
  @moduledoc """
  Provides the `defprompt` macro for declaring MCP prompts alongside their handlers.

  Prompts are user-controlled message templates surfaced to MCP clients via
  `prompts/list` and `prompts/get` (MCP spec 2025-11-25).

  ## Example

      defprompt "code_review", "Ask the model to review code",
        arguments: [code: {:string!, "The code to review"}] do
        {:ok, [
          %{role: "user",
            content: %{type: "text", text: "Please review:\\n" <> params["code"]}}
        ]}
      end

  Inside the `do` block, `params` and `session` are bound.

  ## Arguments

  The `:arguments` keyword uses the same DSL as tool params (see `NexusMCP.Server.Schema`):

      arguments: [
        code: :string!,                     # required string, no description
        language: {:string, "Lang hint"},   # optional string with description
        max_lines: {:integer, "Cap lines"}
      ]

  Required arguments are validated by the session before the handler is invoked;
  missing required args produce a `-32602` JSON-RPC error.
  """

  alias NexusMCP.Server.Schema

  defmacro defprompt(name, description, opts_or_args \\ [], do_block \\ []) do
    opts = Keyword.merge(opts_or_args, do_block)
    {block, opts} = Keyword.pop!(opts, :do)
    args_def = Keyword.get(opts, :arguments, [])

    arguments = build_arguments(args_def)

    prompt_def = %{
      name: name,
      description: description,
      arguments: arguments
    }

    quote do
      @__nexus_prompts__ unquote(Macro.escape(prompt_def))

      def __nexus_handle_prompt_get__(unquote(name), var!(params), var!(session)) do
        _ = var!(params)
        _ = var!(session)
        unquote(block)
      end
    end
  end

  @doc """
  Converts the DSL `arguments:` keyword list to MCP prompt argument objects.

  ## Example

      iex> NexusMCP.Server.Prompt.build_arguments([code: {:string!, "The code"}])
      [%{name: "code", description: "The code", required: true}]
  """
  def build_arguments(args) when is_list(args) do
    Enum.map(args, fn {name, type_spec} ->
      {schema, required} = Schema.type_to_schema(type_spec)
      base = %{name: to_string(name), required: required}

      case Map.get(schema, :description) do
        nil -> base
        desc -> Map.put(base, :description, desc)
      end
    end)
  end

  @doc """
  Returns the names of arguments marked required.
  """
  def required_argument_names(arguments) when is_list(arguments) do
    arguments
    |> Enum.filter(& &1.required)
    |> Enum.map(& &1.name)
  end
end
