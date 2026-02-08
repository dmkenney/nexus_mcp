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
end
