defmodule NexusMCP.TestServerDeftool do
  use NexusMCP.Server,
    name: "test-deftool",
    version: "1.0.0"

  deftool "greet", "Greet someone by name", params: [name: {:string!, "Person's name"}] do
    {:ok, "Hello, #{params["name"]}!"}
  end

  deftool "get_status", "Get server status", params: [] do
    {:ok, %{status: "ok", session_id: session.session_id}}
  end

  deftool "add", "Add two numbers",
    params: [a: {:integer!, "First number"}, b: {:integer!, "Second number"}] do
    {:ok, %{result: params["a"] + params["b"]}}
  end

  deftool "fail_tool", "A tool that fails", params: [] do
    {:error, "intentional failure"}
  end

  deftool "list_items", "List all items",
    params: [],
    annotations: %{readOnlyHint: true, destructiveHint: false} do
    {:ok, []}
  end

  deftool "delete_item", "Delete an item",
    params: [id: {:string!, "Item ID"}],
    annotations: %{readOnlyHint: false, destructiveHint: true, idempotentHint: true} do
    {:ok, %{deleted: true, id: params["id"]}}
  end

  deftool "get_weather", "Get current weather",
    params: [city: {:string!, "City name"}],
    output_schema: %{
      type: "object",
      properties: %{
        temperature: %{type: "number", description: "Temperature in celsius"},
        conditions: %{type: "string", description: "Weather conditions"}
      },
      required: ["temperature", "conditions"]
    } do
    {:ok, %{temperature: 22.5, conditions: "Partly cloudy", city: params["city"]}}
  end

  deftool "audit_log", "Read the audit log",
    params: [],
    annotations: %{readOnlyHint: true, destructiveHint: false},
    output_schema: %{type: "array", items: %{type: "object"}} do
    {:ok, [%{event: "created"}]}
  end
end
