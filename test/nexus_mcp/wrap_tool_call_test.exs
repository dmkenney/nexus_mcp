defmodule NexusMCP.WrapToolCallTest do
  use ExUnit.Case

  import NexusMCP.TestHelpers

  alias NexusMCP.Session

  setup do
    start_supervised!({NexusMCP.Supervisor, []})
    :ok
  end

  describe "default wrap_tool_call" do
    test "is passthrough — existing servers work unchanged" do
      {_id, pid} = start_session(NexusMCP.TestServer)
      initialize(pid)

      result =
        Session.rpc(pid, %{
          method: "tools/call",
          id: 2,
          params: %{"name" => "echo", "arguments" => %{"message" => "hello"}}
        })

      assert %{"result" => %{"content" => [%{"type" => "text", "text" => "hello"}]}} = result
    end
  end

  describe "custom wrap_tool_call" do
    test "sets up process-local state from session assigns" do
      {_id, pid} = start_session(NexusMCP.TestServerWrapToolCall, %{org_id: "org_42"})
      initialize(pid)

      result =
        Session.rpc(pid, %{
          method: "tools/call",
          id: 2,
          params: %{"name" => "check_process_dict", "arguments" => %{}}
        })

      assert %{"result" => %{"content" => [%{"type" => "text", "text" => text}]}} = result
      assert Jason.decode!(text)["org_id"] == "org_42"
    end

    test "wrap_tool_call rescue catches handler errors" do
      {_id, pid} = start_session(NexusMCP.TestServerWrapRescue)
      initialize(pid)

      result =
        Session.rpc(pid, %{
          method: "tools/call",
          id: 2,
          params: %{"name" => "raise_tool", "arguments" => %{}}
        })

      assert %{
               "result" => %{
                 "isError" => true,
                 "content" => [%{"text" => "caught by wrap_tool_call"}]
               }
             } =
               result
    end

    test "wrap_tool_call passes through successful results" do
      {_id, pid} = start_session(NexusMCP.TestServerWrapRescue)
      initialize(pid)

      result =
        Session.rpc(pid, %{
          method: "tools/call",
          id: 2,
          params: %{"name" => "ok_tool", "arguments" => %{}}
        })

      assert %{"result" => %{"content" => [%{"type" => "text", "text" => "all good"}]}} = result
    end
  end
end
