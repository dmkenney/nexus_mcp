defmodule NexusMCP.Server.SchemaTest do
  use ExUnit.Case, async: true

  alias NexusMCP.Server.Schema

  describe "type_to_schema/1" do
    test "basic types" do
      assert {%{type: "string"}, false} = Schema.type_to_schema(:string)
      assert {%{type: "string"}, true} = Schema.type_to_schema(:string!)
      assert {%{type: "integer"}, false} = Schema.type_to_schema(:integer)
      assert {%{type: "integer"}, true} = Schema.type_to_schema(:integer!)
      assert {%{type: "boolean"}, false} = Schema.type_to_schema(:boolean)
      assert {%{type: "boolean"}, true} = Schema.type_to_schema(:boolean!)
      assert {%{type: "number"}, false} = Schema.type_to_schema(:number)
      assert {%{type: "number"}, true} = Schema.type_to_schema(:number!)
      assert {%{type: "object"}, false} = Schema.type_to_schema(:object)
      assert {%{type: "object"}, true} = Schema.type_to_schema(:object!)
    end

    test "with description" do
      assert {%{type: "string", description: "A name"}, true} =
               Schema.type_to_schema({:string!, "A name"})

      assert {%{type: "integer", description: "Count"}, false} =
               Schema.type_to_schema({:integer, "Count"})
    end

    test "array types" do
      assert {%{type: "array", items: %{type: "string"}}, false} =
               Schema.type_to_schema({:array, :string})

      assert {%{type: "array", items: %{type: "integer"}}, true} =
               Schema.type_to_schema({:array!, :integer})
    end

    test "array with description" do
      assert {%{type: "array", items: %{type: "string"}, description: "Tags"}, false} =
               Schema.type_to_schema({{:array, :string}, "Tags"})
    end
  end

  describe "params_to_schema/1" do
    test "empty params" do
      assert %{type: "object", properties: %{}} = Schema.params_to_schema([])
    end

    test "all optional params have no required key" do
      schema = Schema.params_to_schema(name: :string, count: :integer)
      assert %{type: "object", properties: props} = schema
      assert map_size(props) == 2
      assert props["name"] == %{type: "string"}
      assert props["count"] == %{type: "integer"}
      refute Map.has_key?(schema, :required)
    end

    test "all required params" do
      schema = Schema.params_to_schema(name: :string!, count: :integer!)
      assert schema.required == ["name", "count"]
    end

    test "mixed required and optional" do
      schema =
        Schema.params_to_schema(
          title: :string!,
          slug: :string,
          priority: {:integer, "Priority level"}
        )

      assert schema.required == ["title"]
      assert schema.properties["title"] == %{type: "string"}
      assert schema.properties["slug"] == %{type: "string"}
      assert schema.properties["priority"] == %{type: "integer", description: "Priority level"}
    end

    test "with descriptions" do
      schema =
        Schema.params_to_schema(
          title: {:string!, "Page title"},
          tags: {{:array, :string}, "Tags"}
        )

      assert schema.required == ["title"]
      assert schema.properties["title"] == %{type: "string", description: "Page title"}

      assert schema.properties["tags"] == %{
               type: "array",
               items: %{type: "string"},
               description: "Tags"
             }
    end

    test "preserves param order in required list" do
      schema =
        Schema.params_to_schema(
          alpha: :string!,
          beta: :string!,
          gamma: :string!
        )

      assert schema.required == ["alpha", "beta", "gamma"]
    end
  end

  describe "make_optional/1" do
    test "strips required from all types" do
      params = [
        name: :string!,
        count: :integer!,
        active: :boolean!,
        score: :number!,
        data: :object!
      ]

      result = Schema.make_optional(params)

      assert result == [
               name: :string,
               count: :integer,
               active: :boolean,
               score: :number,
               data: :object
             ]
    end

    test "leaves optional types unchanged" do
      params = [name: :string, count: :integer]
      assert Schema.make_optional(params) == params
    end

    test "handles descriptions" do
      params = [title: {:string!, "Page title"}, slug: {:string, "URL slug"}]
      result = Schema.make_optional(params)

      assert result == [
               title: {:string, "Page title"},
               slug: {:string, "URL slug"}
             ]
    end

    test "handles array types" do
      params = [tags: {:array, :string}, ids: {:array!, :integer}]
      result = Schema.make_optional(params)
      assert result == [tags: {:array, :string}, ids: {:array, :integer}]
    end

    test "empty params" do
      assert Schema.make_optional([]) == []
    end
  end
end
