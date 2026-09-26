defmodule NexusMCP.ToolVisibilityTest do
  use ExUnit.Case

  import NexusMCP.TestHelpers

  alias NexusMCP.Session

  setup do
    start_supervised!({NexusMCP.Supervisor, []})
    :ok
  end

  defp list_tools(pid) do
    %{"result" => %{"tools" => tools}} =
      Session.rpc(pid, %{method: "tools/list", id: 2, params: %{}})

    tools
  end

  defp call_tool(pid, name) do
    Session.rpc(pid, %{
      method: "tools/call",
      id: 3,
      params: %{"name" => name, "arguments" => %{}}
    })
  end

  defp start_visibility_session(assigns) do
    {_id, pid} =
      start_session(NexusMCP.TestServerToolVisibility, Map.put(assigns, :test_pid, self()))

    initialize(pid)
    pid
  end

  describe "default tool_visible?" do
    test "lists every tool" do
      {_id, pid} = start_session(NexusMCP.TestServerDeftool)
      initialize(pid)

      names = pid |> list_tools() |> Enum.map(& &1.name)
      assert names == Enum.map(NexusMCP.TestServerDeftool.tools(), & &1.name)
    end
  end

  describe "tools/list" do
    test "hides tools the session may not see" do
      pid = start_visibility_session(%{admin: false})

      assert pid |> list_tools() |> Enum.map(& &1.name) == ["public_tool"]
    end

    test "lists them for a session that may see them" do
      pid = start_visibility_session(%{admin: true})

      assert pid |> list_tools() |> Enum.map(& &1.name) ==
               ["public_tool", "admin_tool", "admin_report"]
    end

    test "does not send meta to clients" do
      pid = start_visibility_session(%{admin: true})
      tools = list_tools(pid)

      refute Enum.any?(tools, &Map.has_key?(&1, :meta))
      refute Jason.encode!(tools) =~ "meta"
    end

    test "meta stays on the tool definition" do
      tool = Enum.find(NexusMCP.TestServerToolVisibility.tools(), &(&1.name == "admin_tool"))
      assert tool.meta == %{admin: true}
    end
  end

  describe "tools/call" do
    test "a hidden tool gets the unknown-tool response without running handlers" do
      pid = start_visibility_session(%{admin: false})

      unknown = call_tool(pid, "no_such_tool")
      # Unknown names still go through wrap_tool_call/2.
      assert_received :wrap_tool_call

      hidden = call_tool(pid, "admin_tool")

      assert hidden ==
               put_in(unknown, ["result", "content"], [
                 %{"type" => "text", "text" => ~s(Unknown tool: "admin_tool")}
               ])

      assert unknown["result"] == %{
               "content" => [%{"type" => "text", "text" => ~s(Unknown tool: "no_such_tool")}],
               "isError" => true
             }

      refute_received :wrap_tool_call
      refute_received {:handle_tool_call, _}
    end

    test "a visible tool runs as before" do
      pid = start_visibility_session(%{admin: true})

      assert %{"result" => %{"content" => [%{"type" => "text", "text" => "admin"}]}} =
               call_tool(pid, "admin_tool")

      assert_received :wrap_tool_call
      assert_received {:handle_tool_call, "admin_tool"}
    end

    test "a visible tool keeps structured output" do
      pid = start_visibility_session(%{admin: true})

      assert %{"result" => %{"structuredContent" => %{count: 3}}} =
               call_tool(pid, "admin_report")
    end

    test "tools visible to everyone still run for other sessions" do
      pid = start_visibility_session(%{admin: false})

      assert %{"result" => %{"content" => [%{"text" => "public"}]}} =
               call_tool(pid, "public_tool")

      assert_received {:handle_tool_call, "public_tool"}
    end
  end
end
