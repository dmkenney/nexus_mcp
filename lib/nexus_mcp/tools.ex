defmodule NexusMCP.Tools do
  @moduledoc """
  A module that only declares tools, for splitting a server by domain.

      defmodule MyApp.MCP.Tools.Pages do
        use NexusMCP.Tools

        deftool "get_page", "Get a page", params: [id: {:string!, "Page ID"}] do
          {:ok, MyApp.CMS.get_page!(params["id"])}
        end
      end

      defmodule MyApp.MCP.Server do
        use NexusMCP.Server,
          name: "myapp",
          version: "1.0.0",
          tools: [MyApp.MCP.Tools.Pages, MyApp.MCP.Tools.Blog]
      end

  `deftool` takes the same options as in a server module (`params`,
  `annotations`, `output_schema`, `meta`), and `params` and `session` are bound
  in the handler the same way.

  The server's `tools/0` returns its own `deftool`s first, then each listed
  module's tools in list order. Its `handle_tool_call/3` and
  `__nexus_handle_tool_call__/3` dispatch to the module that declared the tool,
  so `c:NexusMCP.Server.wrap_tool_call/2`, `c:NexusMCP.Server.tool_visible?/2`
  and a custom `handle_tool_call/3` work as they do for the server's own tools.

  ## Module defaults

  Options given to `use NexusMCP.Tools` apply to every tool in the module:

      use NexusMCP.Tools,
        params: [account_id: {:string!, "Account ID (use list_accounts to find)"}],
        meta: %{admin: true},
        annotations: %{readOnlyHint: false}

    * `:params` - added before each tool's own params. A tool that declares a
      param with the same key replaces the default. A tool opts out of defaults
      with `skip_default_params: [:account_id]`.
    * `:meta` - merged recursively with the tool's `meta`; the tool's values win.
    * `:annotations` - merged with the tool's `annotations`; the tool's values win.

  `use NexusMCP.Server` accepts the same options for the server's own tools.

  ## Recompilation

  The server reads its tools modules when it compiles, as it does its own
  `deftool`s: `tools/0` returns a fixed list and dispatch is one function
  clause per tool name, with nothing looked up at runtime. The server
  therefore has a compile-time dependency on each listed module and recompiles
  whenever one of them changes.

  A tool name declared twice (in the server or any listed module) and a listed
  module that does not use `NexusMCP.Tools` are compile errors in the server.
  """

  defmacro __using__(opts) do
    location = {__CALLER__.file, __CALLER__.line}
    defaults = Keyword.take(opts, [:params, :meta, :annotations])

    case Keyword.keys(opts) -- [:params, :meta, :annotations] do
      [] ->
        :ok

      unknown ->
        NexusMCP.Server.Tool.compile_error!(
          __CALLER__.file,
          __CALLER__.line,
          "unknown options for use NexusMCP.Tools: #{inspect(unknown)}"
        )
    end

    quote do
      Module.register_attribute(__MODULE__, :__nexus_tools__, accumulate: true)
      Module.register_attribute(__MODULE__, :__nexus_tool_sources__, accumulate: true)

      Module.put_attribute(
        __MODULE__,
        :__nexus_tool_defaults__,
        NexusMCP.Server.Tool.__defaults__(unquote(defaults), unquote(location))
      )

      @before_compile NexusMCP.Tools

      import NexusMCP.Server.Tool, only: [deftool: 3, deftool: 4, format_changeset_errors: 1]
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    tools = env.module |> Module.get_attribute(:__nexus_tools__, []) |> Enum.reverse()
    sources = env.module |> Module.get_attribute(:__nexus_tool_sources__, []) |> Enum.reverse()
    NexusMCP.Server.Tool.check_duplicates!(sources)

    # Read by the server at compile time. The server dispatches straight to
    # this module's `__nexus_tool_call__/3` clauses.
    quote do
      @doc false
      def __nexus_tools__, do: unquote(Macro.escape(tools))

      @doc false
      def __nexus_tool_sources__, do: unquote(Macro.escape(sources))
    end
  end
end
