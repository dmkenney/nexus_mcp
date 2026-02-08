defmodule NexusMCP.SSE do
  @moduledoc """
  SSE (Server-Sent Events) connection handler.

  Manages the chunked response loop for SSE streams. Sends keepalive
  comments periodically to detect broken connections.
  """

  require Logger

  @keepalive_interval 30_000

  @doc """
  Start an SSE stream on the given connection.

  Sends the initial headers and enters a receive loop. This function
  blocks until the connection is closed or an error occurs.
  """
  def start_stream(conn, session_pid) do
    conn =
      conn
      |> Plug.Conn.put_resp_header("content-type", "text/event-stream")
      |> Plug.Conn.put_resp_header("cache-control", "no-cache")
      |> Plug.Conn.put_resp_header("connection", "keep-alive")
      |> Plug.Conn.send_chunked(200)

    NexusMCP.Session.register_sse(session_pid, self())
    schedule_keepalive()
    loop(conn)
  end

  defp loop(conn) do
    receive do
      {:sse_event, data} ->
        case send_event(conn, data) do
          {:ok, conn} -> loop(conn)
          {:error, _reason} -> conn
        end

      :keepalive ->
        case Plug.Conn.chunk(conn, ": keepalive\n\n") do
          {:ok, conn} ->
            schedule_keepalive()
            loop(conn)

          {:error, _reason} ->
            conn
        end

      :close ->
        conn
    end
  end

  defp send_event(conn, data) when is_binary(data) do
    Plug.Conn.chunk(conn, "data: #{data}\n\n")
  end

  defp send_event(conn, data) do
    send_event(conn, Jason.encode!(data))
  end

  defp schedule_keepalive do
    Process.send_after(self(), :keepalive, @keepalive_interval)
  end
end
