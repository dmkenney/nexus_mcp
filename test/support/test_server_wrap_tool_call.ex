defmodule NexusMCP.TestServerWrapToolCall do
  use NexusMCP.Server,
    name: "test-wrap",
    version: "1.0.0"

  @impl true
  def wrap_tool_call(session, fun) do
    Process.put(:wrap_org_id, session.assigns[:org_id])
    fun.()
  end

  deftool "check_process_dict", "Check process dictionary", params: [] do
    {:ok, %{org_id: Process.get(:wrap_org_id)}}
  end

  deftool "echo_wrap", "Echo for wrap test", params: [message: :string] do
    {:ok, params["message"]}
  end
end

defmodule NexusMCP.TestServerWrapRescue do
  use NexusMCP.Server,
    name: "test-wrap-rescue",
    version: "1.0.0"

  @impl true
  def wrap_tool_call(_session, fun) do
    fun.()
  rescue
    RuntimeError -> {:error, "caught by wrap_tool_call"}
  end

  deftool "raise_tool", "A tool that raises", params: [] do
    raise "boom"
  end

  deftool "ok_tool", "A tool that succeeds", params: [] do
    {:ok, "all good"}
  end
end
