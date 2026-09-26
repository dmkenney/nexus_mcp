defmodule NexusMCP.ToolModulesTest do
  use ExUnit.Case

  import NexusMCP.TestHelpers

  alias NexusMCP.Session
  alias NexusMCP.TestServerToolModules, as: Server

  setup do
    start_supervised!({NexusMCP.Supervisor, []})
    :ok
  end

  defp list_tools(pid) do
    %{"result" => %{"tools" => tools}} =
      Session.rpc(pid, %{method: "tools/list", id: 2, params: %{}})

    tools
  end

  defp call_tool(pid, name, args \\ %{}) do
    Session.rpc(pid, %{
      method: "tools/call",
      id: 3,
      params: %{"name" => name, "arguments" => args}
    })
  end

  defp start_modules_session(server \\ Server, assigns) do
    {_id, pid} = start_session(server, Map.put(assigns, :test_pid, self()))
    initialize(pid)
    pid
  end

  defp decoded_text(%{"result" => %{"content" => [%{"text" => text}]}}), do: Jason.decode!(text)

  describe "tools/0" do
    test "returns the server's own tools, then each module's in list order" do
      assert Enum.map(Server.tools(), & &1.name) == [
               "server_ping",
               "get_page",
               "rename_page",
               "list_accounts",
               "search_pages",
               "admin_delete_template",
               "admin_stats"
             ]
    end

    test "tools/list returns every visible tool in order" do
      pid = start_modules_session(%{admin: true})

      assert pid |> list_tools() |> Enum.map(& &1.name) ==
               Enum.map(Server.tools(), & &1.name)
    end
  end

  describe "dispatch" do
    test "calls go to the module that declared the tool, with params and session bound" do
      pid = start_modules_session(%{admin: true})

      assert %{"module" => "pages", "params" => %{"id" => "p1"}, "session_id" => session_id} =
               pid |> call_tool("get_page", %{"id" => "p1"}) |> decoded_text()

      assert is_binary(session_id)
      assert_received :wrap_tool_call

      assert %{"module" => "admin"} = pid |> call_tool("admin_stats") |> decoded_text()
      assert %{"module" => "server"} = pid |> call_tool("server_ping") |> decoded_text()
    end

    test "helpers defined in a tools module work in handlers" do
      session = %{session_id: "s", assigns: %{}}

      assert {:ok, %{renamed: "p1", title: "HOME"}} =
               Server.handle_tool_call("rename_page", %{"id" => "p1", "title" => "home"}, session)
    end

    test "structured output works for module tools" do
      pid = start_modules_session(%{admin: true})

      assert %{"result" => %{"structuredContent" => %{deleted: "t1"}}} =
               call_tool(pid, "admin_delete_template", %{"id" => "t1"})
    end

    test "unknown tools get the unknown-tool response" do
      pid = start_modules_session(%{admin: true})

      assert call_tool(pid, "no_such_tool")["result"] == %{
               "content" => [%{"type" => "text", "text" => ~s(Unknown tool: "no_such_tool")}],
               "isError" => true
             }

      session = %{session_id: "s", assigns: %{}}
      assert {:error, _} = Server.__nexus_handle_tool_call__("no_such_tool", %{}, session)
    end

    test "a server overriding handle_tool_call/3 reaches module tools" do
      auth = NexusMCP.TestServerToolModulesAuth
      session = %{session_id: "s", assigns: %{}}

      assert {:ok, %{module: "pages"}} =
               auth.handle_tool_call("get_page", %{"id" => "1"}, session)

      assert {:error, "denied"} =
               auth.handle_tool_call("get_page", %{}, %{session | assigns: %{denied: true}})

      pid = start_modules_session(auth, %{})

      assert %{"module" => "pages"} =
               pid |> call_tool("get_page", %{"id" => "1"}) |> decoded_text()
    end

    test "tools of a module not listed in tools: are unknown" do
      session = %{session_id: "s", assigns: %{}}

      assert {:error, ~s(Unknown tool: "admin_stats")} =
               NexusMCP.TestServerToolModulesAuth.handle_tool_call("admin_stats", %{}, session)
    end
  end

  describe "tool_visible?/2" do
    test "sees the module's default meta merged with the tool's" do
      delete = Enum.find(Server.tools(), &(&1.name == "admin_delete_template"))
      stats = Enum.find(Server.tools(), &(&1.name == "admin_stats"))

      assert delete.meta == %{admin: true, tags: %{area: "admin", danger: true}}
      assert stats.meta == %{admin: false, tags: %{area: "admin"}}
    end

    test "hides admin module tools from other sessions" do
      pid = start_modules_session(%{admin: false})
      names = pid |> list_tools() |> Enum.map(& &1.name)

      refute "admin_delete_template" in names
      assert "admin_stats" in names

      assert %{"result" => %{"isError" => true}} =
               call_tool(pid, "admin_delete_template", %{"id" => "t1"})

      refute_received {:handle_tool_call, _}
    end

    test "meta is not sent to clients" do
      pid = start_modules_session(%{admin: true})
      refute pid |> list_tools() |> Jason.encode!() =~ "meta"
    end
  end
end
