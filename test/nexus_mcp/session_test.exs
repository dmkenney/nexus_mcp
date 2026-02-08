defmodule NexusMCP.SessionTest do
  use ExUnit.Case

  import NexusMCP.TestHelpers

  alias NexusMCP.Session

  setup do
    start_supervised!({NexusMCP.Supervisor, []})
    :ok
  end

  describe "initialize" do
    test "returns server capabilities" do
      {_id, pid} = start_session()
      result = initialize(pid)

      assert %{"jsonrpc" => "2.0", "id" => 1, "result" => result_body} = result
      assert result_body["protocolVersion"] == "2025-03-26"
      assert result_body["serverInfo"]["name"] == "test-server"
      assert result_body["capabilities"]["tools"]
    end

    test "fails if already initialized" do
      {_id, pid} = start_session()
      initialize(pid)
      result = initialize(pid)

      assert %{"error" => %{"code" => -32600}} = result
    end

    test "custom init callback updates assigns" do
      {_id, pid} = start_session(NexusMCP.TestServerWithInit)
      result = initialize(pid)
      assert %{"result" => _} = result
    end

    test "failed init callback returns error" do
      {_id, pid} = start_session(NexusMCP.TestServerFailInit)
      result = initialize(pid)
      assert %{"error" => %{"message" => msg}} = result
      assert msg =~ "init refused"
    end
  end

  describe "ping" do
    test "responds with empty result" do
      {_id, pid} = start_session()
      result = Session.rpc(pid, %{method: "ping", id: 2, params: %{}})
      assert %{"result" => %{}} = result
    end
  end

  describe "notifications/initialized" do
    test "returns :notification" do
      {_id, pid} = start_session()
      initialize(pid)
      result = Session.rpc(pid, %{method: "notifications/initialized", id: nil, params: %{}})
      assert result == :notification
    end
  end

  describe "tools/list" do
    test "returns tools after initialization" do
      {_id, pid} = start_session()
      initialize(pid)
      result = Session.rpc(pid, %{method: "tools/list", id: 2, params: %{}})

      assert %{"result" => %{"tools" => tools}} = result
      assert length(tools) > 0
      assert Enum.any?(tools, &(&1.name == "echo"))
    end

    test "fails if not initialized" do
      {_id, pid} = start_session()
      result = Session.rpc(pid, %{method: "tools/list", id: 2, params: %{}})
      assert %{"error" => %{"code" => -32600}} = result
    end
  end

  describe "tools/call" do
    test "calls a tool and returns result" do
      {_id, pid} = start_session()
      initialize(pid)

      result =
        Session.rpc(pid, %{
          method: "tools/call",
          id: 3,
          params: %{"name" => "echo", "arguments" => %{"message" => "hello"}}
        })

      assert %{"result" => %{"content" => [%{"type" => "text", "text" => "hello"}]}} = result
    end

    test "handles tool errors" do
      {_id, pid} = start_session()
      initialize(pid)

      result =
        Session.rpc(pid, %{
          method: "tools/call",
          id: 3,
          params: %{"name" => "failing_tool", "arguments" => %{}}
        })

      assert %{
               "result" => %{
                 "isError" => true,
                 "content" => [%{"text" => "This tool always fails"}]
               }
             } = result
    end

    test "handles tool crashes" do
      {_id, pid} = start_session()
      initialize(pid)

      result =
        Session.rpc(pid, %{
          method: "tools/call",
          id: 3,
          params: %{"name" => "crash_tool", "arguments" => %{}}
        })

      assert %{"error" => %{"code" => -32603}} = result
    end

    test "returns map results as JSON" do
      {_id, pid} = start_session()
      initialize(pid)

      result =
        Session.rpc(pid, %{
          method: "tools/call",
          id: 3,
          params: %{"name" => "map_result", "arguments" => %{}}
        })

      assert %{"result" => %{"content" => [%{"type" => "text", "text" => text}]}} = result
      assert Jason.decode!(text) == %{"key" => "value"}
    end

    test "returns pre-formatted string-keyed content items as-is" do
      {_id, pid} = start_session()
      initialize(pid)

      result =
        Session.rpc(pid, %{
          method: "tools/call",
          id: 3,
          params: %{"name" => "list_result", "arguments" => %{}}
        })

      assert %{"result" => %{"content" => [%{"text" => "item1"}, %{"text" => "item2"}]}} = result
    end

    test "returns pre-formatted atom-keyed content items as-is" do
      {_id, pid} = start_session()
      initialize(pid)

      result =
        Session.rpc(pid, %{
          method: "tools/call",
          id: 3,
          params: %{"name" => "list_atom_content", "arguments" => %{}}
        })

      assert %{"result" => %{"content" => [%{text: "atom1"}, %{text: "atom2"}]}} = result
    end

    test "JSON-encodes a list of plain maps" do
      {_id, pid} = start_session()
      initialize(pid)

      result =
        Session.rpc(pid, %{
          method: "tools/call",
          id: 3,
          params: %{"name" => "list_of_maps", "arguments" => %{}}
        })

      assert %{"result" => %{"content" => [%{"type" => "text", "text" => text}]}} = result
      decoded = Jason.decode!(text)
      assert is_list(decoded)
      assert length(decoded) == 2
      assert hd(decoded)["title"] == "Page One"
    end

    test "JSON-encodes an empty list" do
      {_id, pid} = start_session()
      initialize(pid)

      result =
        Session.rpc(pid, %{
          method: "tools/call",
          id: 3,
          params: %{"name" => "empty_list", "arguments" => %{}}
        })

      assert %{"result" => %{"content" => [%{"type" => "text", "text" => "[]"}]}} = result
    end

    test "passes assigns to tool calls" do
      {_id, pid} = start_session(NexusMCP.TestServer, %{org_id: "org_123"})
      initialize(pid)

      result =
        Session.rpc(pid, %{
          method: "tools/call",
          id: 3,
          params: %{"name" => "check_assigns", "arguments" => %{}}
        })

      assert %{"result" => %{"content" => [%{"text" => text}]}} = result
      assert Jason.decode!(text) == %{"org_id" => "org_123"}
    end

    test "concurrent tool calls don't block each other" do
      {_id, pid} = start_session()
      initialize(pid)

      # Start two slow tool calls concurrently
      task1 =
        Task.async(fn ->
          Session.rpc(pid, %{
            method: "tools/call",
            id: 10,
            params: %{"name" => "slow_tool", "arguments" => %{"delay_ms" => 100}}
          })
        end)

      task2 =
        Task.async(fn ->
          Session.rpc(pid, %{
            method: "tools/call",
            id: 11,
            params: %{"name" => "slow_tool", "arguments" => %{"delay_ms" => 100}}
          })
        end)

      start = System.monotonic_time(:millisecond)
      Task.await(task1)
      Task.await(task2)
      elapsed = System.monotonic_time(:millisecond) - start

      # If serialized, would take ~200ms. Concurrent should be ~100ms.
      assert elapsed < 180
    end

    test "fails if not initialized" do
      {_id, pid} = start_session()

      result =
        Session.rpc(pid, %{
          method: "tools/call",
          id: 3,
          params: %{"name" => "echo", "arguments" => %{"message" => "hi"}}
        })

      assert %{"error" => %{"code" => -32600}} = result
    end
  end

  describe "unknown method" do
    test "returns method not found for requests" do
      {_id, pid} = start_session()
      result = Session.rpc(pid, %{method: "nonexistent", id: 99, params: %{}})
      assert %{"error" => %{"code" => -32601}} = result
    end

    test "returns notification for unknown notifications" do
      {_id, pid} = start_session()
      result = Session.rpc(pid, %{method: "nonexistent", id: nil, params: %{}})
      assert result == :notification
    end
  end

  describe "registry" do
    test "session is discoverable via registry" do
      {session_id, pid} = start_session()
      registry = NexusMCP.SessionRegistry.impl()

      assert {:ok, ^pid} = registry.lookup(session_id)
    end

    test "session disappears from registry when stopped" do
      {session_id, pid} = start_session()

      ref = Process.monitor(pid)
      GenServer.stop(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, _}, 500

      await_registry_cleanup(session_id)
    end
  end

  describe "idle timeout" do
    test "session dies after idle timeout" do
      {_id, pid} = start_session(NexusMCP.TestServerShortTimeout)
      ref = Process.monitor(pid)

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 500
    end

    test "activity resets idle timeout" do
      {_id, pid} = start_session(NexusMCP.TestServerShortTimeout)
      initialize(pid)

      # Keep pinging to reset timeout
      Process.sleep(60)
      Session.rpc(pid, %{method: "ping", id: 2, params: %{}})
      Process.sleep(60)
      Session.rpc(pid, %{method: "ping", id: 3, params: %{}})
      Process.sleep(60)

      # Session should still be alive after 180ms total (timeout is 100ms)
      assert Process.alive?(pid)
    end
  end

  describe "session expiry → 404 (Anubis bug #1)" do
    test "timed-out session disappears from registry" do
      {session_id, pid} = start_session(NexusMCP.TestServerShortTimeout)
      registry = NexusMCP.SessionRegistry.impl()
      ref = Process.monitor(pid)

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 500
      assert :error = registry.lookup(session_id)
    end

    test "RPC to dead session exits with noproc" do
      {_id, pid} = start_session(NexusMCP.TestServerShortTimeout)
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 500

      assert catch_exit(Session.rpc(pid, %{method: "ping", id: 1, params: %{}}))
    end
  end

  describe "SSE connection monitoring (Anubis bug #2)" do
    test "session tracks SSE connections" do
      {_id, pid} = start_session()
      initialize(pid)

      # Simulate an SSE connection by registering self
      Session.register_sse(pid, self())

      # Session should still be alive
      assert Process.alive?(pid)
    end

    test "session detects dead SSE connection" do
      {_id, pid} = start_session()
      initialize(pid)

      # Spawn a fake SSE process and register it
      sse_pid =
        spawn(fn ->
          receive do
            :stop -> :ok
          end
        end)

      Session.register_sse(pid, sse_pid)

      # Kill the SSE process
      Process.exit(sse_pid, :kill)
      Process.sleep(50)

      # Session should still be alive (SSE death doesn't kill session)
      assert Process.alive?(pid)
    end
  end

  describe "zombie session prevention (Anubis bug #3)" do
    test "tools/call on uninitialized session returns error, not silent re-creation" do
      {_id, pid} = start_session()

      # Don't initialize — go straight to tool call
      result =
        Session.rpc(pid, %{
          method: "tools/call",
          id: 1,
          params: %{"name" => "echo", "arguments" => %{"message" => "hi"}}
        })

      assert %{"error" => %{"code" => -32600, "message" => "Not initialized"}} = result
    end

    test "tools/list on uninitialized session returns error" do
      {_id, pid} = start_session()
      result = Session.rpc(pid, %{method: "tools/list", id: 1, params: %{}})
      assert %{"error" => %{"code" => -32600, "message" => "Not initialized"}} = result
    end
  end

  describe "init callback affects subsequent tool calls" do
    test "assigns modified in init/1 are visible in handle_tool_call/3" do
      {_id, pid} = start_session(NexusMCP.TestServerWithInit, %{original: "value"})
      initialize(pid)

      result =
        Session.rpc(pid, %{
          method: "tools/call",
          id: 2,
          params: %{"name" => "read_assigns", "arguments" => %{}}
        })

      assert %{"result" => %{"content" => [%{"text" => text}]}} = result
      assigns = Jason.decode!(text)
      assert assigns["initialized_at"] == "test"
      assert assigns["original"] == "value"
    end
  end

  describe "edge cases" do
    test "ping works without initialization" do
      {_id, pid} = start_session()
      result = Session.rpc(pid, %{method: "ping", id: 1, params: %{}})
      assert %{"result" => %{}} = result
    end

    test "tools/call with missing arguments defaults to empty map" do
      {_id, pid} = start_session()
      initialize(pid)

      result =
        Session.rpc(pid, %{
          method: "tools/call",
          id: 3,
          params: %{"name" => "list_of_maps"}
        })

      assert %{"result" => %{"content" => [%{"type" => "text", "text" => _}]}} = result
    end

    test "integer tool result is converted to string" do
      {_id, pid} = start_session(NexusMCP.TestServerEdgeCases)
      initialize(pid)

      result =
        Session.rpc(pid, %{
          method: "tools/call",
          id: 3,
          params: %{"name" => "integer_result", "arguments" => %{}}
        })

      assert %{"result" => %{"content" => [%{"type" => "text", "text" => "42"}]}} = result
    end

    test "nil tool result is converted to string" do
      {_id, pid} = start_session(NexusMCP.TestServerEdgeCases)
      initialize(pid)

      result =
        Session.rpc(pid, %{
          method: "tools/call",
          id: 3,
          params: %{"name" => "nil_result", "arguments" => %{}}
        })

      assert %{"result" => %{"content" => [%{"type" => "text", "text" => ""}]}} = result
    end

    test "non-string error is inspected" do
      {_id, pid} = start_session(NexusMCP.TestServerEdgeCases)
      initialize(pid)

      result =
        Session.rpc(pid, %{
          method: "tools/call",
          id: 3,
          params: %{"name" => "tuple_error", "arguments" => %{}}
        })

      assert %{"result" => %{"isError" => true, "content" => [%{"text" => text}]}} = result
      assert text =~ "something_went_wrong"
    end

    test "duplicate session ID is rejected" do
      {session_id, _pid} = start_session()
      registry = NexusMCP.SessionRegistry.impl()

      # Try to register a second process with the same ID
      result = registry.register(session_id, self())
      assert {:error, :already_registered} = result
    end
  end
end
