defmodule NexusMCP.Server.ToolTest do
  use ExUnit.Case, async: true

  describe "deftool generates correct tools/0" do
    test "returns all defined tools" do
      tools = NexusMCP.TestServerDeftool.tools()
      assert length(tools) == 8

      names = Enum.map(tools, & &1.name)
      assert "greet" in names
      assert "get_status" in names
      assert "add" in names
      assert "fail_tool" in names
      assert "list_items" in names
      assert "delete_item" in names
      assert "get_weather" in names
      assert "audit_log" in names
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

    test "tools with annotations include annotations map" do
      tools = NexusMCP.TestServerDeftool.tools()
      list_items = Enum.find(tools, &(&1.name == "list_items"))

      assert list_items.annotations == %{readOnlyHint: true, destructiveHint: false}
    end

    test "tools with destructive annotations" do
      tools = NexusMCP.TestServerDeftool.tools()
      delete_item = Enum.find(tools, &(&1.name == "delete_item"))

      assert delete_item.annotations == %{
               readOnlyHint: false,
               destructiveHint: true,
               idempotentHint: true
             }
    end

    test "tools without annotations have no annotations key" do
      tools = NexusMCP.TestServerDeftool.tools()
      greet = Enum.find(tools, &(&1.name == "greet"))

      refute Map.has_key?(greet, :annotations)
    end

    test "output_schema is advertised as outputSchema" do
      tools = NexusMCP.TestServerDeftool.tools()
      weather = Enum.find(tools, &(&1.name == "get_weather"))

      assert weather.outputSchema == %{
               type: "object",
               properties: %{
                 temperature: %{type: "number", description: "Temperature in celsius"},
                 conditions: %{type: "string", description: "Weather conditions"}
               },
               required: ["temperature", "conditions"]
             }
    end

    test "output_schema composes with annotations" do
      tools = NexusMCP.TestServerDeftool.tools()
      audit_log = Enum.find(tools, &(&1.name == "audit_log"))

      assert audit_log.annotations == %{readOnlyHint: true, destructiveHint: false}

      assert audit_log.outputSchema == %{
               type: "object",
               properties: %{entries: %{type: "array", items: %{type: "object"}}},
               required: ["entries"]
             }
    end

    test "tools without output_schema have no outputSchema key" do
      tools = NexusMCP.TestServerDeftool.tools()
      greet = Enum.find(tools, &(&1.name == "greet"))

      refute Map.has_key?(greet, :outputSchema)
    end
  end

  describe "output schema validation" do
    test "accepts an object root schema" do
      assert :ok =
               NexusMCP.Server.Tool.validate_output_schema!("t", %{
                 type: "object",
                 properties: %{}
               })
    end

    test "accepts string keys, as a manual tools/0 would use" do
      assert :ok = NexusMCP.Server.Tool.validate_output_schema!("t", %{"type" => "object"})
    end

    test "rejects an array root schema" do
      assert_raise ArgumentError, ~r/restricts output schemas/, fn ->
        NexusMCP.Server.Tool.validate_output_schema!("audit_log", %{
          type: "array",
          items: %{type: "object"}
        })
      end
    end

    test "rejects a scalar root schema" do
      assert_raise ArgumentError, ~r/root type "string"/, fn ->
        NexusMCP.Server.Tool.validate_output_schema!("t", %{type: "string"})
      end
    end

    test "rejects a schema with no root type" do
      assert_raise ArgumentError, ~r/root type nil/, fn ->
        NexusMCP.Server.Tool.validate_output_schema!("t", %{properties: %{}})
      end
    end

    test "rejects a non-map schema" do
      assert_raise ArgumentError, ~r/not a map/, fn ->
        NexusMCP.Server.Tool.validate_output_schema!("t", "object")
      end
    end

    test "deftool raises when the declared schema is not an object" do
      assert_raise ArgumentError, ~r/restricts output schemas/, fn ->
        defmodule InvalidOutputSchemaServer do
          use NexusMCP.Server, name: "invalid", version: "1.0.0"

          deftool "bad", "Declares an array output schema",
            params: [],
            output_schema: %{type: "array", items: %{type: "object"}} do
            {:ok, []}
          end
        end
      end
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
