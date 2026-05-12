defmodule NexusMCP.Server.Compile do
  @moduledoc false

  # Single `@before_compile` hook for `NexusMCP.Server` users.
  #
  # Reads the `@__nexus_tools__`, `@__nexus_prompts__`, `@__nexus_resources__`,
  # and `@__nexus_resource_templates__` attributes accumulated by the
  # `deftool` / `defprompt` / `defresource` / `defresource_template` macros and
  # generates the corresponding behaviour callbacks plus dispatch functions.
  #
  # If the user did not use the DSL for a given primitive, no-op defaults are
  # emitted instead. Defaults live here (not in `Server.__using__/1`) because
  # `defoverridable` doesn't apply to definitions injected by `@before_compile`.

  defmacro __before_compile__(env) do
    tools = env.module |> Module.get_attribute(:__nexus_tools__, []) |> Enum.reverse()
    prompts = env.module |> Module.get_attribute(:__nexus_prompts__, []) |> Enum.reverse()
    resources = env.module |> Module.get_attribute(:__nexus_resources__, []) |> Enum.reverse()

    templates =
      env.module |> Module.get_attribute(:__nexus_resource_templates__, []) |> Enum.reverse()

    has_manual_tools = Module.defines?(env.module, {:tools, 0})
    has_manual_handle_tool = Module.defines?(env.module, {:handle_tool_call, 3})
    has_manual_prompts = Module.defines?(env.module, {:prompts, 0})
    has_manual_handle_prompt = Module.defines?(env.module, {:handle_prompt_get, 3})
    has_manual_resources = Module.defines?(env.module, {:resources, 0})
    has_manual_resource_templates = Module.defines?(env.module, {:resource_templates, 0})
    has_manual_handle_resource = Module.defines?(env.module, {:handle_resource_read, 3})

    if tools != [] and has_manual_tools do
      raise CompileError,
        file: env.file,
        line: 0,
        description:
          "#{inspect(env.module)} defines both deftool and a manual tools/0. " <>
            "Use one or the other."
    end

    [
      tools_quote(tools, has_manual_tools, has_manual_handle_tool),
      prompts_quote(prompts, has_manual_prompts, has_manual_handle_prompt),
      resources_quote(
        resources,
        templates,
        has_manual_resources,
        has_manual_resource_templates,
        has_manual_handle_resource
      )
    ]
  end

  # --- Tools ---

  defp tools_quote([], has_manual_tools, has_manual_handle_tool) do
    [
      unless(has_manual_tools,
        do:
          quote do
            @impl NexusMCP.Server
            def tools, do: []
          end
      ),
      unless(has_manual_handle_tool,
        do:
          quote do
            @impl NexusMCP.Server
            def handle_tool_call(_name, _params, _session), do: {:error, "Unknown tool"}
          end
      )
    ]
  end

  defp tools_quote(tools, _has_manual_tools, has_manual_handle_tool) do
    [
      quote do
        @impl NexusMCP.Server
        def tools, do: unquote(Macro.escape(tools))
      end,
      unless(has_manual_handle_tool,
        do:
          quote do
            @impl NexusMCP.Server
            def handle_tool_call(name, params, session) do
              __nexus_handle_tool_call__(name, params, session)
            end
          end
      )
    ]
  end

  # --- Prompts ---

  defp prompts_quote([], has_manual_prompts, has_manual_handle_prompt) do
    [
      unless(has_manual_prompts,
        do:
          quote do
            @impl NexusMCP.Server
            def prompts, do: []
          end
      ),
      unless(has_manual_handle_prompt,
        do:
          quote do
            @impl NexusMCP.Server
            def handle_prompt_get(_name, _args, _session), do: {:error, :not_found}
          end
      )
    ]
  end

  defp prompts_quote(prompts, _has_manual_prompts, has_manual_handle_prompt) do
    [
      quote do
        @impl NexusMCP.Server
        def prompts, do: unquote(Macro.escape(prompts))
      end,
      unless(has_manual_handle_prompt,
        do:
          quote do
            @impl NexusMCP.Server
            def handle_prompt_get(name, args, session) do
              __nexus_handle_prompt_get__(name, args, session)
            end
          end
      )
    ]
  end

  # --- Resources ---

  defp resources_quote([], [], has_manual_resources, has_manual_templates, has_manual_read) do
    [
      unless(has_manual_resources,
        do:
          quote do
            @impl NexusMCP.Server
            def resources, do: []
          end
      ),
      unless(has_manual_templates,
        do:
          quote do
            @impl NexusMCP.Server
            def resource_templates, do: []
          end
      ),
      unless(has_manual_read,
        do:
          quote do
            @impl NexusMCP.Server
            def handle_resource_read(_uri, _params, _session), do: {:error, :not_found}
          end
      )
    ]
  end

  defp resources_quote(
         resources,
         templates,
         has_manual_resources,
         has_manual_templates,
         has_manual_read
       ) do
    public_templates = Enum.map(templates, &NexusMCP.Server.Resource.public_template/1)
    static_uris = Enum.map(resources, & &1.uri)
    has_static = resources != []
    has_templates = templates != []

    static_clause =
      if has_static do
        quote do
          if uri in unquote(static_uris) do
            __nexus_handle_resource_read__(uri, params, session)
          end
        end
      end

    template_clause =
      if has_templates do
        quote do
          case NexusMCP.Server.Resource.match_template(uri, unquote(Macro.escape(templates))) do
            {:ok, template, captures} ->
              __nexus_handle_resource_read_template__(template.uriTemplate, captures, session)

            :error ->
              {:error, :not_found}
          end
        end
      else
        quote do
          {:error, :not_found}
        end
      end

    handler_body =
      if has_static do
        quote do
          case unquote(static_clause) do
            nil -> unquote(template_clause)
            result -> result
          end
        end
      else
        template_clause
      end

    [
      unless(has_manual_resources,
        do:
          quote do
            @impl NexusMCP.Server
            def resources, do: unquote(Macro.escape(resources))
          end
      ),
      unless(has_manual_templates,
        do:
          quote do
            @impl NexusMCP.Server
            def resource_templates, do: unquote(Macro.escape(public_templates))
          end
      ),
      unless(has_manual_read,
        do:
          quote do
            @impl NexusMCP.Server
            def handle_resource_read(uri, params, session) do
              unquote(handler_body)
            end
          end
      )
    ]
  end
end
