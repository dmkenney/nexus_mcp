defmodule NexusMCP.Transport do
  @moduledoc """
  Plug-based HTTP transport for MCP Streamable HTTP spec.

  Routes HTTP methods:
  - **POST** — JSON-RPC requests/notifications
  - **GET** — SSE stream for server-to-client push
  - **DELETE** — Session termination

  ## Usage in Router

      forward "/mcp", NexusMCP.Transport, server: MyApp.MCP

  ## Options

  - `:server` — The module implementing `NexusMCP.Server` (required)
  """

  @behaviour Plug

  import Plug.Conn
  require Logger

  alias NexusMCP.{JsonRpc, Session, SSE}

  @impl true
  def init(opts) do
    server = Keyword.fetch!(opts, :server)
    %{server: server}
  end

  @impl true
  def call(conn, %{server: server}) do
    case conn.method do
      "POST" -> handle_post(conn, server)
      "GET" -> handle_get(conn)
      "DELETE" -> handle_delete(conn)
      _ -> send_resp(conn, 405, "Method Not Allowed")
    end
  end

  # --- POST: JSON-RPC ---

  defp handle_post(conn, server) do
    with {:ok, body} <- read_body_params(conn),
         {:ok, request} <- JsonRpc.decode(body) do
      if request.method == "initialize" do
        handle_initialize(conn, server, request)
      else
        handle_session_rpc(conn, request)
      end
    else
      {:error, %{"jsonrpc" => _} = error_response} ->
        json_response(conn, 200, error_response)

      {:error, :no_body} ->
        json_response(
          conn,
          400,
          JsonRpc.error(nil, JsonRpc.parse_error_code(), "Empty request body")
        )
    end
  end

  defp handle_initialize(conn, server, request) do
    session_id = generate_session_id()
    assigns = Map.get(conn.assigns, :nexus_mcp_assigns, %{})

    case start_session(session_id, server, assigns) do
      {:ok, pid} ->
        response = call_session(pid, request)

        case response do
          :session_dead ->
            json_response(
              conn,
              500,
              JsonRpc.error(
                request.id,
                JsonRpc.internal_error_code(),
                "Session died during initialization"
              )
            )

          %{"error" => _} ->
            # Init callback failed, stop the session
            DynamicSupervisor.terminate_child(NexusMCP.SessionSupervisor, pid)
            json_response(conn, 200, response)

          _ ->
            conn
            |> put_resp_header("mcp-session-id", session_id)
            |> json_response(200, response)
        end

      {:error, reason} ->
        Logger.error("Failed to start session: #{inspect(reason)}")

        json_response(
          conn,
          500,
          JsonRpc.error(request.id, JsonRpc.internal_error_code(), "Failed to create session")
        )
    end
  end

  defp handle_session_rpc(conn, request) do
    case get_session_pid(conn) do
      {:ok, pid} ->
        response = call_session(pid, request)

        case response do
          :session_dead ->
            send_resp(conn, 404, "Session not found")

          :notification ->
            send_resp(conn, 202, "")

          _ ->
            session_id = get_req_header(conn, "mcp-session-id") |> List.first()

            conn
            |> put_resp_header("mcp-session-id", session_id)
            |> json_response(200, response)
        end

      {:error, :missing_session_id} ->
        json_response(
          conn,
          400,
          JsonRpc.error(nil, JsonRpc.invalid_request_code(), "Missing Mcp-Session-Id header")
        )

      {:error, :not_found} ->
        send_resp(conn, 404, "Session not found")
    end
  end

  # --- GET: SSE ---

  defp handle_get(conn) do
    accepts = get_req_header(conn, "accept")

    if Enum.any?(accepts, &String.contains?(&1, "text/event-stream")) do
      case get_session_pid(conn) do
        {:ok, pid} ->
          SSE.start_stream(conn, pid)

        {:error, :missing_session_id} ->
          send_resp(conn, 400, "Missing Mcp-Session-Id header")

        {:error, :not_found} ->
          send_resp(conn, 404, "Session not found")
      end
    else
      send_resp(conn, 406, "Not Acceptable: must accept text/event-stream")
    end
  end

  # --- DELETE: Session termination ---

  defp handle_delete(conn) do
    case get_session_pid(conn) do
      {:ok, pid} ->
        DynamicSupervisor.terminate_child(NexusMCP.SessionSupervisor, pid)
        send_resp(conn, 204, "")

      {:error, :missing_session_id} ->
        send_resp(conn, 400, "Missing Mcp-Session-Id header")

      {:error, :not_found} ->
        send_resp(conn, 404, "Session not found")
    end
  end

  # --- Helpers ---

  defp read_body_params(%{body_params: %Plug.Conn.Unfetched{}} = conn) do
    case Plug.Conn.read_body(conn) do
      {:ok, body, _conn} ->
        case Jason.decode(body) do
          {:ok, decoded} -> {:ok, decoded}
          {:error, _} -> {:error, JsonRpc.error(nil, JsonRpc.parse_error_code(), "Parse error")}
        end

      {:error, _} ->
        {:error, :no_body}
    end
  end

  defp read_body_params(%{body_params: %{}} = conn) do
    {:ok, conn.body_params}
  end

  defp get_session_pid(conn) do
    case get_req_header(conn, "mcp-session-id") do
      [session_id | _] ->
        registry = NexusMCP.SessionRegistry.impl()

        case registry.lookup(session_id) do
          {:ok, pid} -> {:ok, pid}
          :error -> {:error, :not_found}
        end

      [] ->
        {:error, :missing_session_id}
    end
  end

  defp start_session(session_id, server_module, assigns) do
    DynamicSupervisor.start_child(
      NexusMCP.SessionSupervisor,
      {Session,
       [
         session_id: session_id,
         server_module: server_module,
         assigns: assigns
       ]}
    )
  end

  defp call_session(pid, request) do
    Session.rpc(pid, request)
  catch
    :exit, {:noproc, _} -> :session_dead
    :exit, {:normal, _} -> :session_dead
    :exit, {:shutdown, _} -> :session_dead
  end

  defp json_response(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end

  defp generate_session_id do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  end
end
