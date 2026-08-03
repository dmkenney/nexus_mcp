defmodule NexusMCP.TestServer do
  use NexusMCP.Server,
    name: "test-server",
    version: "1.0.0"

  @impl true
  def tools do
    [
      %{
        name: "echo",
        description: "Echo back the input",
        inputSchema: %{type: "object", properties: %{"message" => %{type: "string"}}}
      },
      %{
        name: "slow_tool",
        description: "A slow tool for testing concurrency",
        inputSchema: %{type: "object", properties: %{"delay_ms" => %{type: "integer"}}}
      },
      %{
        name: "failing_tool",
        description: "A tool that always fails",
        inputSchema: %{type: "object", properties: %{}}
      },
      %{
        name: "crash_tool",
        description: "A tool that crashes",
        inputSchema: %{type: "object", properties: %{}}
      },
      %{
        name: "map_result",
        description: "Returns a map result",
        inputSchema: %{type: "object", properties: %{}}
      },
      %{
        name: "list_result",
        description: "Returns a list of content items",
        inputSchema: %{type: "object", properties: %{}}
      },
      %{
        name: "check_assigns",
        description: "Returns the session assigns",
        inputSchema: %{type: "object", properties: %{}}
      },
      %{
        name: "list_of_maps",
        description: "Returns a list of plain maps (like list_pages)",
        inputSchema: %{type: "object", properties: %{}}
      },
      %{
        name: "list_atom_content",
        description: "Returns atom-keyed content items",
        inputSchema: %{type: "object", properties: %{}}
      },
      %{
        name: "empty_list",
        description: "Returns an empty list",
        inputSchema: %{type: "object", properties: %{}}
      },
      %{
        name: "structured_map",
        description: "Returns a map and declares an output schema",
        inputSchema: %{type: "object", properties: %{}},
        outputSchema: %{
          type: "object",
          properties: %{"temperature" => %{type: "number"}},
          required: ["temperature"]
        }
      },
      %{
        name: "structured_list",
        description: "Returns a bare list despite declaring an output schema",
        inputSchema: %{type: "object", properties: %{}},
        outputSchema: %{
          type: "object",
          properties: %{entries: %{type: "array", items: %{type: "object"}}},
          required: ["entries"]
        }
      },
      %{
        name: "structured_failing",
        description: "Declares an output schema but returns an error",
        inputSchema: %{type: "object", properties: %{}},
        outputSchema: %{type: "object"}
      }
    ]
  end

  @impl true
  def handle_tool_call("echo", %{"message" => message}, _session) do
    {:ok, message}
  end

  def handle_tool_call("slow_tool", %{"delay_ms" => delay}, _session) do
    Process.sleep(delay)
    {:ok, "done after #{delay}ms"}
  end

  def handle_tool_call("failing_tool", _params, _session) do
    {:error, "This tool always fails"}
  end

  def handle_tool_call("crash_tool", _params, _session) do
    raise "boom!"
  end

  def handle_tool_call("map_result", _params, _session) do
    {:ok, %{"key" => "value"}}
  end

  def handle_tool_call("structured_map", _params, _session) do
    {:ok, %{"temperature" => 22.5}}
  end

  def handle_tool_call("structured_list", _params, _session) do
    {:ok, [%{"id" => "1"}, %{"id" => "2"}]}
  end

  def handle_tool_call("structured_failing", _params, _session) do
    {:error, "could not fetch data"}
  end

  def handle_tool_call("list_result", _params, _session) do
    {:ok, [%{"type" => "text", "text" => "item1"}, %{"type" => "text", "text" => "item2"}]}
  end

  def handle_tool_call("check_assigns", _params, session) do
    {:ok, Jason.encode!(session.assigns)}
  end

  def handle_tool_call("list_of_maps", _params, _session) do
    {:ok, [%{id: "1", title: "Page One"}, %{id: "2", title: "Page Two"}]}
  end

  def handle_tool_call("list_atom_content", _params, _session) do
    {:ok, [%{type: "text", text: "atom1"}, %{type: "text", text: "atom2"}]}
  end

  def handle_tool_call("empty_list", _params, _session) do
    {:ok, []}
  end
end
