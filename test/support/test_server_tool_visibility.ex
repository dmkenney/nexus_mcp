defmodule NexusMCP.TestServerToolVisibility do
  use NexusMCP.Server,
    name: "test-tool-visibility",
    version: "1.0.0"

  @impl true
  def tool_visible?(%{meta: %{admin: true}}, session), do: session.assigns[:admin] == true
  def tool_visible?(_tool, _session), do: true

  @impl true
  def wrap_tool_call(session, fun) do
    send(session.assigns.test_pid, :wrap_tool_call)
    fun.()
  end

  deftool "public_tool", "Visible to everyone", params: [] do
    send(session.assigns.test_pid, {:handle_tool_call, "public_tool"})
    {:ok, "public"}
  end

  deftool "admin_tool", "Visible to admins only",
    params: [],
    meta: %{admin: true} do
    send(session.assigns.test_pid, {:handle_tool_call, "admin_tool"})
    {:ok, "admin"}
  end

  deftool "admin_report", "Structured admin report",
    params: [],
    meta: %{admin: true},
    output_schema: %{
      type: "object",
      properties: %{count: %{type: "integer"}},
      required: ["count"]
    } do
    {:ok, %{count: 3}}
  end
end
