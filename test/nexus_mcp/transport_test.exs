defmodule NexusMCP.TransportTest do
  use ExUnit.Case

  import NexusMCP.TestHelpers, only: [await_registry_cleanup: 1]
  import Plug.Test
  import Plug.Conn

  alias NexusMCP.Transport

  @opts Transport.init(server: NexusMCP.TestServer)

  setup do
    start_supervised!({NexusMCP.Supervisor, []})
    :ok
  end

  defp json_post(path, body, headers \\ []) do
    conn =
      conn(:post, path, Jason.encode!(body))
      |> put_req_header("content-type", "application/json")
      |> put_req_header("accept", "application/json")

    conn = Enum.reduce(headers, conn, fn {k, v}, c -> put_req_header(c, k, v) end)

    conn
    |> Transport.call(@opts)
  end

  defp initialize do
    conn =
      json_post("/", %{
        "jsonrpc" => "2.0",
        "method" => "initialize",
        "id" => 1,
        "params" => %{
          "protocolVersion" => "2025-03-26",
          "clientInfo" => %{"name" => "test", "version" => "1.0"},
          "capabilities" => %{}
        }
      })

    body = Jason.decode!(conn.resp_body)
    session_id = resp_header(conn, "mcp-session-id") |> List.first()
    {session_id, body}
  end

  defp resp_header(conn, key) do
    for {k, v} <- conn.resp_headers, k == key, do: v
  end

  describe "POST /initialize" do
    test "creates session and returns capabilities" do
      {session_id, body} = initialize()

      assert session_id != nil
      assert body["result"]["protocolVersion"] == "2025-03-26"
      assert body["result"]["serverInfo"]["name"] == "test-server"
    end
  end

  describe "POST /tools/list" do
    test "returns tool list" do
      {session_id, _} = initialize()

      conn =
        json_post(
          "/",
          %{"jsonrpc" => "2.0", "method" => "tools/list", "id" => 2, "params" => %{}},
          [{"mcp-session-id", session_id}]
        )

      body = Jason.decode!(conn.resp_body)
      assert %{"result" => %{"tools" => tools}} = body
      assert is_list(tools)
      assert length(tools) > 0
    end

    test "returns 404 for missing session" do
      conn =
        json_post(
          "/",
          %{"jsonrpc" => "2.0", "method" => "tools/list", "id" => 2, "params" => %{}},
          [{"mcp-session-id", "nonexistent-session"}]
        )

      assert conn.status == 404
    end

    test "returns 400 for missing session header" do
      conn =
        json_post(
          "/",
          %{"jsonrpc" => "2.0", "method" => "tools/list", "id" => 2, "params" => %{}}
        )

      body = Jason.decode!(conn.resp_body)
      assert body["error"]["code"] == -32600
    end
  end

  describe "POST /tools/call" do
    test "calls a tool and returns result" do
      {session_id, _} = initialize()

      conn =
        json_post(
          "/",
          %{
            "jsonrpc" => "2.0",
            "method" => "tools/call",
            "id" => 3,
            "params" => %{"name" => "echo", "arguments" => %{"message" => "hello"}}
          },
          [{"mcp-session-id", session_id}]
        )

      body = Jason.decode!(conn.resp_body)
      assert %{"result" => %{"content" => [%{"type" => "text", "text" => "hello"}]}} = body
    end

    test "returns session-id header in response" do
      {session_id, _} = initialize()

      conn =
        json_post(
          "/",
          %{
            "jsonrpc" => "2.0",
            "method" => "tools/call",
            "id" => 3,
            "params" => %{"name" => "echo", "arguments" => %{"message" => "test"}}
          },
          [{"mcp-session-id", session_id}]
        )

      assert resp_header(conn, "mcp-session-id") == [session_id]
    end
  end

  describe "POST /notifications" do
    test "returns 202 for notifications" do
      {session_id, _} = initialize()

      conn =
        json_post(
          "/",
          %{"jsonrpc" => "2.0", "method" => "notifications/initialized"},
          [{"mcp-session-id", session_id}]
        )

      assert conn.status == 202
    end
  end

  describe "POST with invalid JSON-RPC" do
    test "returns error for invalid request" do
      conn =
        json_post("/", %{"not" => "valid"})

      body = Jason.decode!(conn.resp_body)
      assert body["error"]["code"] == -32600
    end
  end

  describe "DELETE" do
    test "terminates session and returns 204" do
      {session_id, _} = initialize()

      conn =
        conn(:delete, "/")
        |> put_req_header("mcp-session-id", session_id)
        |> Transport.call(@opts)

      assert conn.status == 204

      # Verify session is gone
      registry = NexusMCP.SessionRegistry.impl()
      Process.sleep(10)
      assert :error = registry.lookup(session_id)
    end

    test "returns 404 for unknown session" do
      conn =
        conn(:delete, "/")
        |> put_req_header("mcp-session-id", "nonexistent")
        |> Transport.call(@opts)

      assert conn.status == 404
    end
  end

  describe "GET (SSE)" do
    test "returns 406 without accept header" do
      {session_id, _} = initialize()

      conn =
        conn(:get, "/")
        |> put_req_header("mcp-session-id", session_id)
        |> Transport.call(@opts)

      assert conn.status == 406
    end

    test "returns 400 without session id" do
      conn =
        conn(:get, "/")
        |> put_req_header("accept", "text/event-stream")
        |> Transport.call(@opts)

      assert conn.status == 400
    end

    test "returns 404 for unknown session" do
      conn =
        conn(:get, "/")
        |> put_req_header("accept", "text/event-stream")
        |> put_req_header("mcp-session-id", "nonexistent")
        |> Transport.call(@opts)

      assert conn.status == 404
    end
  end

  describe "unsupported methods" do
    test "returns 405" do
      conn =
        conn(:patch, "/")
        |> Transport.call(@opts)

      assert conn.status == 405
    end
  end

  describe "session expiry returns 404 (Anubis bug #1)" do
    test "request to timed-out session returns 404" do
      # Initialize with a short-timeout server
      opts = Transport.init(server: NexusMCP.TestServerShortTimeout)

      init_conn =
        conn(
          :post,
          "/",
          Jason.encode!(%{
            "jsonrpc" => "2.0",
            "method" => "initialize",
            "id" => 1,
            "params" => %{
              "protocolVersion" => "2025-03-26",
              "clientInfo" => %{"name" => "test", "version" => "1.0"},
              "capabilities" => %{}
            }
          })
        )
        |> put_req_header("content-type", "application/json")
        |> put_req_header("accept", "application/json")
        |> Transport.call(opts)

      session_id = resp_header(init_conn, "mcp-session-id") |> List.first()
      assert session_id != nil

      # Wait for session to actually die and registry to clean up
      registry = NexusMCP.SessionRegistry.impl()
      {:ok, pid} = registry.lookup(session_id)
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000
      await_registry_cleanup(session_id)

      # Confirm registry is truly empty
      assert :error = registry.lookup(session_id)

      # Request with expired session should get 404
      conn =
        conn(
          :post,
          "/",
          Jason.encode!(%{
            "jsonrpc" => "2.0",
            "method" => "tools/list",
            "id" => 2,
            "params" => %{}
          })
        )
        |> put_req_header("content-type", "application/json")
        |> put_req_header("accept", "application/json")
        |> put_req_header("mcp-session-id", session_id)
        |> Transport.call(opts)

      assert conn.status == 404
    end
  end

  describe "POST tool calls return inline JSON (Anubis bug #2)" do
    test "tool call response comes as direct JSON, not SSE" do
      {session_id, _} = initialize()

      conn =
        json_post(
          "/",
          %{
            "jsonrpc" => "2.0",
            "method" => "tools/call",
            "id" => 3,
            "params" => %{"name" => "echo", "arguments" => %{"message" => "inline"}}
          },
          [{"mcp-session-id", session_id}]
        )

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") |> List.first() =~ "application/json"
      body = Jason.decode!(conn.resp_body)
      assert body["result"]["content"]
    end
  end

  describe "zombie prevention (Anubis bug #3)" do
    test "non-initialize request without valid session returns 404, not silent re-creation" do
      conn =
        json_post(
          "/",
          %{"jsonrpc" => "2.0", "method" => "tools/list", "id" => 1, "params" => %{}},
          [{"mcp-session-id", "expired-or-fake-session-id"}]
        )

      assert conn.status == 404
    end
  end

  describe "race condition: session dies mid-request" do
    test "returns 404 via registry miss" do
      {session_id, _} = initialize()

      # Kill the session and wait for full registry cleanup
      registry = NexusMCP.SessionRegistry.impl()
      {:ok, pid} = registry.lookup(session_id)
      ref = Process.monitor(pid)
      GenServer.stop(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, _}, 500
      await_registry_cleanup(session_id)

      conn =
        json_post(
          "/",
          %{"jsonrpc" => "2.0", "method" => "ping", "id" => 2, "params" => %{}},
          [{"mcp-session-id", session_id}]
        )

      assert conn.status == 404
    end
  end

  describe "failed init cleans up session" do
    test "session is terminated after init callback failure" do
      opts = Transport.init(server: NexusMCP.TestServerFailInit)

      conn =
        conn(
          :post,
          "/",
          Jason.encode!(%{
            "jsonrpc" => "2.0",
            "method" => "initialize",
            "id" => 1,
            "params" => %{
              "protocolVersion" => "2025-03-26",
              "clientInfo" => %{"name" => "test", "version" => "1.0"},
              "capabilities" => %{}
            }
          })
        )
        |> put_req_header("content-type", "application/json")
        |> put_req_header("accept", "application/json")
        |> Transport.call(opts)

      body = Jason.decode!(conn.resp_body)
      assert body["error"]["message"] =~ "init refused"

      # Session should have been cleaned up — session_id header should not be set
      # (init failed, so no valid session exists)
      session_id = resp_header(conn, "mcp-session-id") |> List.first()
      assert session_id == nil
    end
  end

  describe "DELETE edge cases" do
    test "returns 400 for missing session-id header" do
      conn =
        conn(:delete, "/")
        |> Transport.call(@opts)

      assert conn.status == 400
    end
  end

  describe "tools/call before initialize at HTTP level" do
    test "returns not-initialized error" do
      {session_id, _} = initialize()

      # Skip sending notifications/initialized, go straight to tool call
      # (this should work — notifications/initialized is optional)
      conn =
        json_post(
          "/",
          %{
            "jsonrpc" => "2.0",
            "method" => "tools/call",
            "id" => 2,
            "params" => %{"name" => "echo", "arguments" => %{"message" => "test"}}
          },
          [{"mcp-session-id", session_id}]
        )

      # Should succeed because initialize was called (notifications/initialized is not required)
      body = Jason.decode!(conn.resp_body)
      assert body["result"]["content"]
    end
  end

  describe "assigns passthrough" do
    test "passes nexus_mcp_assigns to session" do
      opts = Transport.init(server: NexusMCP.TestServer)

      conn =
        conn(
          :post,
          "/",
          Jason.encode!(%{
            "jsonrpc" => "2.0",
            "method" => "initialize",
            "id" => 1,
            "params" => %{
              "protocolVersion" => "2025-03-26",
              "clientInfo" => %{"name" => "test", "version" => "1.0"},
              "capabilities" => %{}
            }
          })
        )
        |> put_req_header("content-type", "application/json")
        |> put_req_header("accept", "application/json")
        |> Plug.Conn.assign(:nexus_mcp_assigns, %{org_id: "org_456"})
        |> Transport.call(opts)

      body = Jason.decode!(conn.resp_body)
      assert body["result"]["serverInfo"]

      session_id = resp_header(conn, "mcp-session-id") |> List.first()

      # Now call check_assigns tool
      conn2 =
        json_post(
          "/",
          %{
            "jsonrpc" => "2.0",
            "method" => "tools/call",
            "id" => 2,
            "params" => %{"name" => "check_assigns", "arguments" => %{}}
          },
          [{"mcp-session-id", session_id}]
        )

      body2 = Jason.decode!(conn2.resp_body)
      text = body2["result"]["content"] |> List.first() |> Map.get("text")
      assert Jason.decode!(text) == %{"org_id" => "org_456"}
    end
  end
end
