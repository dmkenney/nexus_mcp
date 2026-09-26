defmodule NexusMCP.Server.ToolModules do
  @moduledoc false

  # Runtime support for servers that list `NexusMCP.Tools` modules in `tools:`.
  #
  # Tool modules are only called at runtime so the server has no compile-time
  # dependency on them. Dispatch uses a name-to-module map, built on first use
  # and cached in `:persistent_term` per server. A tools module answers a name
  # it does not declare with `not_here/0`; the map is then rebuilt and the call
  # retried once, which covers modules reloaded in development.

  alias NexusMCP.Server.Tool

  @not_here :__nexus_tool_not_here__

  def not_here, do: @not_here

  def tools(own_tools, modules) do
    own_tools ++ Enum.flat_map(modules, & &1.__nexus_tools__())
  end

  def dispatch(server, modules, name, params, session) do
    case Map.fetch(index(server, modules), name) do
      {:ok, module} ->
        case module.__nexus_handle_tool_call__(name, params, session) do
          @not_here -> redispatch(server, modules, name, params, session)
          result -> result
        end

      :error ->
        redispatch(server, modules, name, params, session)
    end
  end

  defp redispatch(server, modules, name, params, session) do
    case Map.fetch(rebuild_index(server, modules), name) do
      {:ok, module} ->
        case module.__nexus_handle_tool_call__(name, params, session) do
          @not_here -> Tool.unknown_tool(name)
          result -> result
        end

      :error ->
        Tool.unknown_tool(name)
    end
  end

  # The module list is stored with the map so a server recompiled with a
  # different `tools:` list never dispatches to a module it no longer lists.
  defp index(server, modules) do
    case :persistent_term.get(key(server), nil) do
      {^modules, index} -> index
      _ -> rebuild_index(server, modules)
    end
  end

  # Rewriting a persistent term is expensive, so only store a changed map.
  # Unknown tool names rebuild the map but leave the stored term alone. On a
  # duplicate name the first module listed wins, matching tools/0 order.
  defp rebuild_index(server, modules) do
    index =
      modules
      |> Enum.reverse()
      |> Enum.flat_map(fn module -> Enum.map(module.__nexus_tools__(), &{&1.name, module}) end)
      |> Map.new()

    entry = {modules, index}

    if :persistent_term.get(key(server), nil) != entry do
      :persistent_term.put(key(server), entry)
    end

    index
  end

  defp key(server), do: {__MODULE__, server}

  @doc false
  # `@after_verify` hook for servers with `tools:` modules.
  def __after_verify__(server) do
    %{modules: modules, sources: sources, location: {file, line}} = server.__nexus_tool_config__()

    module_sources =
      Enum.flat_map(modules, fn module ->
        unless Code.ensure_loaded?(module) and function_exported?(module, :__nexus_tools__, 0) do
          Tool.compile_error!(
            file,
            line,
            "#{inspect(module)} is listed in tools: of #{inspect(server)} but does not " <>
              "use NexusMCP.Tools"
          )
        end

        module.__nexus_tool_sources__()
      end)

    Tool.check_duplicates!(sources ++ module_sources)
  end
end
