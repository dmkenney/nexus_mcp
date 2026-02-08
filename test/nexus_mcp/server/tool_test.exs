defmodule NexusMCP.Server.ToolTest do
  use ExUnit.Case, async: true

  describe "deftool generates correct tools/0" do
    test "returns all defined tools" do
      tools = NexusMCP.TestServerDeftool.tools()
      assert length(tools) == 4

      names = Enum.map(tools, & &1.name)
      assert "greet" in names
      assert "get_status" in names
      assert "add" in names
      assert "fail_tool" in names
    end

    test "tools have correct schemas" do
      tools = NexusMCP.TestServerDeftool.tools()
      greet = Enum.find(tools, &(&1.name == "greet"))

      assert greet.description == "Greet someone by name"
      assert greet.inputSchema.type == "object"

      assert greet.inputSchema.properties["name"] == %{
               type: "string",
               description: "Person's name"
             }

      assert greet.inputSchema.required == ["name"]
    end

    test "tools with multiple required params" do
      tools = NexusMCP.TestServerDeftool.tools()
      add = Enum.find(tools, &(&1.name == "add"))

      assert add.inputSchema.required == ["a", "b"]
      assert add.inputSchema.properties["a"] == %{type: "integer", description: "First number"}
    end

    test "tools with no params" do
      tools = NexusMCP.TestServerDeftool.tools()
      status = Enum.find(tools, &(&1.name == "get_status"))

      assert status.inputSchema == %{type: "object", properties: %{}}
    end
  end

  describe "deftool dispatches correctly" do
    test "handler receives params" do
      session = %{session_id: "test-123", assigns: %{}}

      assert {:ok, "Hello, Alice!"} =
               NexusMCP.TestServerDeftool.handle_tool_call("greet", %{"name" => "Alice"}, session)
    end

    test "handler receives session" do
      session = %{session_id: "sess-456", assigns: %{}}

      assert {:ok, %{status: "ok", session_id: "sess-456"}} =
               NexusMCP.TestServerDeftool.handle_tool_call("get_status", %{}, session)
    end

    test "handler with computation" do
      session = %{session_id: "test", assigns: %{}}

      assert {:ok, %{result: 7}} =
               NexusMCP.TestServerDeftool.handle_tool_call("add", %{"a" => 3, "b" => 4}, session)
    end

    test "handler returning error" do
      session = %{session_id: "test", assigns: %{}}

      assert {:error, "intentional failure"} =
               NexusMCP.TestServerDeftool.handle_tool_call("fail_tool", %{}, session)
    end
  end

  describe "backward compatibility" do
    test "manual tools/0 still works" do
      tools = NexusMCP.TestServer.tools()
      assert length(tools) > 0
      assert Enum.any?(tools, &(&1.name == "echo"))
    end

    test "manual handle_tool_call still works" do
      session = %{session_id: "test", assigns: %{}}

      assert {:ok, "hello"} =
               NexusMCP.TestServer.handle_tool_call("echo", %{"message" => "hello"}, session)
    end
  end

  describe "format_changeset_errors/1" do
    test "formats single error" do
      changeset = %{errors: [name: {"can't be blank", [validation: :required]}]}

      assert {:error, "name: can't be blank"} =
               NexusMCP.Server.Tool.format_changeset_errors(changeset)
    end

    test "formats multiple errors" do
      changeset = %{
        errors: [
          name: {"can't be blank", [validation: :required]},
          email: {"has already been taken", []}
        ]
      }

      assert {:error, msg} = NexusMCP.Server.Tool.format_changeset_errors(changeset)
      assert msg =~ "name: can't be blank"
      assert msg =~ "email: has already been taken"
    end

    test "interpolates values" do
      changeset = %{
        errors: [
          name: {"should be at least %{count} character(s)", [count: 3, validation: :length]}
        ]
      }

      assert {:error, "name: should be at least 3 character(s)"} =
               NexusMCP.Server.Tool.format_changeset_errors(changeset)
    end
  end
end
