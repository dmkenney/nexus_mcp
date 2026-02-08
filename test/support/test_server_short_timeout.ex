defmodule NexusMCP.TestServerShortTimeout do
  use NexusMCP.Server,
    name: "test-short-timeout",
    version: "1.0.0",
    idle_timeout: 100

  @impl true
  def tools, do: []

  @impl true
  def handle_tool_call(_name, _params, _session), do: {:error, "no tools"}
end
