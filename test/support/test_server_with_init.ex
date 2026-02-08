defmodule NexusMCP.TestServerWithInit do
  use NexusMCP.Server,
    name: "test-init-server",
    version: "1.0.0"

  @impl true
  def init(session) do
    assigns = Map.put(session.assigns, :initialized_at, "test")
    {:ok, %{session | assigns: assigns}}
  end

  @impl true
  def tools do
    [
      %{
        name: "read_assigns",
        description: "Read session assigns",
        inputSchema: %{type: "object", properties: %{}}
      }
    ]
  end

  @impl true
  def handle_tool_call("read_assigns", _params, session) do
    {:ok, Jason.encode!(session.assigns)}
  end
end

defmodule NexusMCP.TestServerFailInit do
  use NexusMCP.Server,
    name: "test-fail-init",
    version: "1.0.0"

  @impl true
  def init(_session), do: {:error, "init refused"}

  @impl true
  def tools, do: []

  @impl true
  def handle_tool_call(_name, _params, _session), do: {:error, "no tools"}
end
