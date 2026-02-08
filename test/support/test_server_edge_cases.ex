defmodule NexusMCP.TestServerEdgeCases do
  use NexusMCP.Server,
    name: "test-edge-cases",
    version: "1.0.0"

  @impl true
  def tools do
    [
      %{
        name: "integer_result",
        description: "Returns an integer",
        inputSchema: %{type: "object", properties: %{}}
      },
      %{
        name: "nil_result",
        description: "Returns nil",
        inputSchema: %{type: "object", properties: %{}}
      },
      %{
        name: "tuple_error",
        description: "Returns a non-string error",
        inputSchema: %{type: "object", properties: %{}}
      }
    ]
  end

  @impl true
  def handle_tool_call("integer_result", _params, _session), do: {:ok, 42}
  def handle_tool_call("nil_result", _params, _session), do: {:ok, nil}

  def handle_tool_call("tuple_error", _params, _session),
    do: {:error, {:something_went_wrong, 123}}
end
