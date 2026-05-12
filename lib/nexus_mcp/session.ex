defmodule NexusMCP.Session do
  @moduledoc """
  GenServer representing a single MCP client session.

  Each MCP client gets its own process. Tool calls execute concurrently
  via Tasks. SSE connections are monitored. Process death = session gone = 404.
  """

  use GenServer, restart: :temporary
  require Logger

  alias NexusMCP.JsonRpc

  @protocol_version "2025-11-25"
  @resource_not_found -32_002

  defstruct [
    :session_id,
    :server_module,
    :idle_timeout,
    initialized: false,
    protocol_version: nil,
    client_info: %{},
    client_capabilities: %{},
    assigns: %{},
    sse_connections: %{},
    pending_tasks: %{}
  ]

  # --- Client API ---

  def start_link(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    server_module = Keyword.fetch!(opts, :server_module)
    initial_assigns = Keyword.get(opts, :assigns, %{})

    GenServer.start_link(__MODULE__, {session_id, server_module, initial_assigns})
  end

  @doc """
  Send an RPC request to the session. Returns the response map.
  """
  def rpc(pid, request) do
    GenServer.call(pid, {:rpc, request}, :infinity)
  end

  @doc """
  Register an SSE connection with this session. The session will monitor the pid.
  """
  def register_sse(pid, sse_pid) do
    GenServer.call(pid, {:register_sse, sse_pid})
  end

  # --- GenServer Callbacks ---

  @impl true
  def init({session_id, server_module, initial_assigns}) do
    registry = NexusMCP.SessionRegistry.impl()

    case registry.register(session_id, self()) do
      :ok ->
        idle_timeout = server_module.idle_timeout()

        state = %__MODULE__{
          session_id: session_id,
          server_module: server_module,
          idle_timeout: idle_timeout,
          assigns: initial_assigns
        }

        {:ok, state, idle_timeout}

      {:error, :already_registered} ->
        {:stop, :already_registered}
    end
  end

  @impl true
  def handle_call({:rpc, request}, from, state) do
    dispatch(request, from, state)
  end

  def handle_call({:register_sse, sse_pid}, _from, state) do
    ref = Process.monitor(sse_pid)

    state = %{state | sse_connections: Map.put(state.sse_connections, ref, sse_pid)}
    {:reply, :ok, state, state.idle_timeout}
  end

  @impl true
  def handle_info({ref, result}, %{pending_tasks: pending} = state) when is_reference(ref) do
    # Task completed
    Process.demonitor(ref, [:flush])

    case Map.pop(pending, ref) do
      {{from, request_id}, pending} ->
        response = task_result_to_response(request_id, result)
        GenServer.reply(from, response)
        {:noreply, %{state | pending_tasks: pending}, state.idle_timeout}

      {nil, _} ->
        {:noreply, state, state.idle_timeout}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, %{pending_tasks: pending} = state) do
    # Could be a task crash or an SSE connection drop
    case Map.pop(pending, ref) do
      {{from, request_id}, pending} ->
        # Task crashed
        Logger.error("Tool call task crashed: #{inspect(reason)}")

        response =
          JsonRpc.error(
            request_id,
            JsonRpc.internal_error_code(),
            "Internal error: tool execution failed"
          )

        GenServer.reply(from, response)
        {:noreply, %{state | pending_tasks: pending}, state.idle_timeout}

      {nil, _} ->
        # SSE connection dropped
        state = %{state | sse_connections: Map.delete(state.sse_connections, ref)}
        {:noreply, state, state.idle_timeout}
    end
  end

  def handle_info(:timeout, state) do
    Logger.info(
      "Session #{state.session_id} timed out after #{state.idle_timeout}ms of inactivity"
    )

    {:stop, :normal, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state, state.idle_timeout}
  end

  # --- Method Dispatch ---

  defp dispatch(%{method: "initialize", id: id, params: params}, _from, state) do
    if state.initialized do
      response = JsonRpc.error(id, JsonRpc.invalid_request_code(), "Already initialized")
      {:reply, response, state, state.idle_timeout}
    else
      session_map = %{session_id: state.session_id, assigns: state.assigns}

      case state.server_module.init(session_map) do
        {:ok, updated_session} ->
          info = state.server_module.server_info()

          result = %{
            "protocolVersion" => @protocol_version,
            "capabilities" => build_capabilities(state.server_module),
            "serverInfo" => %{
              "name" => info.name,
              "version" => info.version
            }
          }

          state = %{
            state
            | initialized: true,
              protocol_version: Map.get(params, "protocolVersion"),
              client_info: Map.get(params, "clientInfo", %{}),
              client_capabilities: Map.get(params, "capabilities", %{}),
              assigns: Map.get(updated_session, :assigns, state.assigns)
          }

          {:reply, JsonRpc.result(id, result), state, state.idle_timeout}

        {:error, reason} ->
          response =
            JsonRpc.error(id, JsonRpc.internal_error_code(), "Initialization failed: #{reason}")

          {:reply, response, state, state.idle_timeout}
      end
    end
  end

  defp dispatch(%{method: "notifications/initialized"}, _from, state) do
    {:reply, :notification, state, state.idle_timeout}
  end

  defp dispatch(%{method: "ping", id: id}, _from, state) do
    {:reply, JsonRpc.result(id, %{}), state, state.idle_timeout}
  end

  defp dispatch(%{method: "tools/list", id: id}, _from, state) do
    if state.initialized do
      tools = state.server_module.tools()
      {:reply, JsonRpc.result(id, %{"tools" => tools}), state, state.idle_timeout}
    else
      response = JsonRpc.error(id, JsonRpc.invalid_request_code(), "Not initialized")
      {:reply, response, state, state.idle_timeout}
    end
  end

  defp dispatch(%{method: "tools/call", id: id, params: params}, from, state) do
    if state.initialized do
      tool_name = Map.get(params, "name")
      tool_params = Map.get(params, "arguments", %{})

      # Copy session state for the task
      session_map = %{session_id: state.session_id, assigns: state.assigns}
      server_module = state.server_module

      task =
        Task.Supervisor.async_nolink(NexusMCP.TaskSupervisor, fn ->
          server_module.wrap_tool_call(session_map, fn ->
            server_module.handle_tool_call(tool_name, tool_params, session_map)
          end)
        end)

      pending = Map.put(state.pending_tasks, task.ref, {from, id})
      {:noreply, %{state | pending_tasks: pending}, state.idle_timeout}
    else
      response = JsonRpc.error(id, JsonRpc.invalid_request_code(), "Not initialized")
      {:reply, response, state, state.idle_timeout}
    end
  end

  defp dispatch(%{method: "prompts/list", id: id}, _from, state) do
    if state.initialized do
      prompts = state.server_module.prompts()
      {:reply, JsonRpc.result(id, %{"prompts" => prompts}), state, state.idle_timeout}
    else
      response = JsonRpc.error(id, JsonRpc.invalid_request_code(), "Not initialized")
      {:reply, response, state, state.idle_timeout}
    end
  end

  defp dispatch(%{method: "prompts/get", id: id, params: params}, _from, state) do
    if state.initialized do
      name = Map.get(params, "name")
      args = Map.get(params, "arguments", %{})

      case find_prompt(state.server_module, name) do
        nil ->
          response =
            JsonRpc.error(id, JsonRpc.invalid_params_code(), "Unknown prompt: #{inspect(name)}")

          {:reply, response, state, state.idle_timeout}

        prompt ->
          case validate_prompt_args(prompt, args) do
            :ok ->
              session_map = %{session_id: state.session_id, assigns: state.assigns}
              response = call_prompt_get(state.server_module, name, args, session_map, prompt, id)
              {:reply, response, state, state.idle_timeout}

            {:error, missing} ->
              response =
                JsonRpc.error(
                  id,
                  JsonRpc.invalid_params_code(),
                  "Missing required argument: #{missing}"
                )

              {:reply, response, state, state.idle_timeout}
          end
      end
    else
      response = JsonRpc.error(id, JsonRpc.invalid_request_code(), "Not initialized")
      {:reply, response, state, state.idle_timeout}
    end
  end

  defp dispatch(%{method: "resources/list", id: id}, _from, state) do
    if state.initialized do
      resources = state.server_module.resources()
      {:reply, JsonRpc.result(id, %{"resources" => resources}), state, state.idle_timeout}
    else
      response = JsonRpc.error(id, JsonRpc.invalid_request_code(), "Not initialized")
      {:reply, response, state, state.idle_timeout}
    end
  end

  defp dispatch(%{method: "resources/templates/list", id: id}, _from, state) do
    if state.initialized do
      templates = state.server_module.resource_templates()

      {:reply, JsonRpc.result(id, %{"resourceTemplates" => templates}), state, state.idle_timeout}
    else
      response = JsonRpc.error(id, JsonRpc.invalid_request_code(), "Not initialized")
      {:reply, response, state, state.idle_timeout}
    end
  end

  defp dispatch(%{method: "resources/read", id: id, params: params}, _from, state) do
    if state.initialized do
      uri = Map.get(params, "uri")
      session_map = %{session_id: state.session_id, assigns: state.assigns}

      response = call_resource_read(state.server_module, uri, session_map, id)
      {:reply, response, state, state.idle_timeout}
    else
      response = JsonRpc.error(id, JsonRpc.invalid_request_code(), "Not initialized")
      {:reply, response, state, state.idle_timeout}
    end
  end

  defp dispatch(%{method: method, id: id}, _from, state) when not is_nil(id) do
    response = JsonRpc.error(id, JsonRpc.method_not_found_code(), "Method not found: #{method}")
    {:reply, response, state, state.idle_timeout}
  end

  defp dispatch(%{method: _method, id: nil}, _from, state) do
    # Unknown notification — ignore
    {:reply, :notification, state, state.idle_timeout}
  end

  # --- Helpers ---

  defp task_result_to_response(request_id, {:ok, result}) when is_binary(result) do
    JsonRpc.result(request_id, %{
      "content" => [%{"type" => "text", "text" => result}]
    })
  end

  defp task_result_to_response(request_id, {:ok, result}) when is_list(result) do
    if content_items?(result) do
      JsonRpc.result(request_id, %{"content" => result})
    else
      JsonRpc.result(request_id, %{
        "content" => [%{"type" => "text", "text" => Jason.encode!(result)}]
      })
    end
  end

  defp task_result_to_response(request_id, {:ok, result}) when is_map(result) do
    JsonRpc.result(request_id, %{
      "content" => [%{"type" => "text", "text" => Jason.encode!(result)}]
    })
  end

  defp task_result_to_response(request_id, {:ok, result}) do
    JsonRpc.result(request_id, %{
      "content" => [%{"type" => "text", "text" => to_string(result)}]
    })
  end

  defp task_result_to_response(request_id, {:error, message}) when is_binary(message) do
    JsonRpc.result(request_id, %{
      "content" => [%{"type" => "text", "text" => message}],
      "isError" => true
    })
  end

  defp task_result_to_response(request_id, {:error, message}) do
    JsonRpc.result(request_id, %{
      "content" => [%{"type" => "text", "text" => inspect(message)}],
      "isError" => true
    })
  end

  defp task_result_to_response(request_id, other) do
    Logger.error("Unexpected tool call result: #{inspect(other)}")

    JsonRpc.error(
      request_id,
      JsonRpc.internal_error_code(),
      "Internal error: unexpected tool result"
    )
  end

  # Check if a list looks like pre-formatted MCP content items.
  # Accepts both string-keyed (%{"type" => "text"}) and atom-keyed (%{type: "text"}).
  defp content_items?([]), do: false

  defp content_items?(items) do
    Enum.all?(items, fn
      %{"type" => t} when is_binary(t) -> true
      %{type: t} when is_binary(t) -> true
      _ -> false
    end)
  end

  # --- Capability declaration ---

  defp build_capabilities(server_module) do
    base = %{"tools" => %{"listChanged" => false}}

    base
    |> maybe_put_capability("prompts", server_module.prompts() != [], %{"listChanged" => false})
    |> maybe_put_capability(
      "resources",
      server_module.resources() != [] or server_module.resource_templates() != [],
      %{"subscribe" => false, "listChanged" => false}
    )
  end

  defp maybe_put_capability(caps, _key, false, _value), do: caps
  defp maybe_put_capability(caps, key, true, value), do: Map.put(caps, key, value)

  # --- Prompts helpers ---

  defp find_prompt(server_module, name) when is_binary(name) do
    Enum.find(server_module.prompts(), fn p -> p.name == name end)
  end

  defp find_prompt(_, _), do: nil

  defp validate_prompt_args(%{arguments: arguments}, args) when is_list(arguments) do
    missing =
      arguments
      |> Enum.filter(& &1.required)
      |> Enum.map(& &1.name)
      |> Enum.find(fn name -> not Map.has_key?(args, name) end)

    case missing do
      nil -> :ok
      name -> {:error, name}
    end
  end

  defp validate_prompt_args(_, _), do: :ok

  defp call_prompt_get(server_module, name, args, session_map, prompt, id) do
    case server_module.handle_prompt_get(name, args, session_map) do
      {:ok, messages} when is_list(messages) ->
        result =
          %{"messages" => messages}
          |> maybe_put_string("description", Map.get(prompt, :description))

        JsonRpc.result(id, result)

      {:error, :not_found} ->
        JsonRpc.error(id, JsonRpc.invalid_params_code(), "Unknown prompt: #{inspect(name)}")

      {:error, reason} ->
        JsonRpc.error(id, JsonRpc.internal_error_code(), to_string(reason))

      other ->
        Logger.error("Unexpected prompts/get result: #{inspect(other)}")

        JsonRpc.error(
          id,
          JsonRpc.internal_error_code(),
          "Internal error: unexpected prompt result"
        )
    end
  end

  defp maybe_put_string(map, _key, nil), do: map
  defp maybe_put_string(map, key, value), do: Map.put(map, key, value)

  # --- Resources helpers ---

  defp call_resource_read(_server_module, nil, _session_map, id) do
    JsonRpc.error(id, JsonRpc.invalid_params_code(), "Missing required parameter: uri")
  end

  defp call_resource_read(server_module, uri, session_map, id) do
    case server_module.handle_resource_read(uri, %{}, session_map) do
      {:ok, content} ->
        mime = resource_mime(server_module, uri)
        contents = [shape_resource_content(uri, mime, content)]
        JsonRpc.result(id, %{"contents" => contents})

      {:error, :not_found} ->
        JsonRpc.error(id, @resource_not_found, "Resource not found", %{"uri" => uri})

      {:error, reason} ->
        JsonRpc.error(id, JsonRpc.internal_error_code(), to_string(reason))

      other ->
        Logger.error("Unexpected resources/read result: #{inspect(other)}")

        JsonRpc.error(
          id,
          JsonRpc.internal_error_code(),
          "Internal error: unexpected resource result"
        )
    end
  end

  defp resource_mime(server_module, uri) do
    static = Enum.find(server_module.resources(), fn r -> r.uri == uri end)

    cond do
      static && Map.get(static, :mimeType) ->
        static.mimeType

      true ->
        Enum.find_value(server_module.resource_templates(), fn t ->
          Map.get(t, :mimeType)
        end)
    end
  end

  defp shape_resource_content(uri, mime, %{text: text} = m) do
    base_resource_map(uri, m[:mimeType] || m["mimeType"] || mime) |> Map.put("text", text)
  end

  defp shape_resource_content(uri, mime, %{"text" => text} = m) do
    base_resource_map(uri, m[:mimeType] || m["mimeType"] || mime) |> Map.put("text", text)
  end

  defp shape_resource_content(uri, mime, %{blob: blob} = m) do
    base_resource_map(uri, m[:mimeType] || m["mimeType"] || mime) |> Map.put("blob", blob)
  end

  defp shape_resource_content(uri, mime, %{"blob" => blob} = m) do
    base_resource_map(uri, m[:mimeType] || m["mimeType"] || mime) |> Map.put("blob", blob)
  end

  defp shape_resource_content(uri, mime, binary) when is_binary(binary) do
    if textual_mime?(mime) do
      base_resource_map(uri, mime) |> Map.put("text", binary)
    else
      base_resource_map(uri, mime) |> Map.put("blob", Base.encode64(binary))
    end
  end

  defp base_resource_map(uri, nil), do: %{"uri" => uri}
  defp base_resource_map(uri, mime), do: %{"uri" => uri, "mimeType" => mime}

  defp textual_mime?(nil), do: true
  defp textual_mime?("text/" <> _), do: true
  defp textual_mime?("application/json"), do: true
  defp textual_mime?("application/json" <> _), do: true
  defp textual_mime?(_), do: false
end
