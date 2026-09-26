[
  %{
    description: "Greet someone by name",
    inputSchema: %{
      properties: %{"name" => %{description: "Person's name", type: "string"}},
      required: ["name"],
      type: "object"
    },
    name: "greet"
  },
  %{
    description: "Get server status",
    inputSchema: %{properties: %{}, type: "object"},
    name: "get_status"
  },
  %{
    description: "Add two numbers",
    inputSchema: %{
      properties: %{
        "a" => %{description: "First number", type: "integer"},
        "b" => %{description: "Second number", type: "integer"}
      },
      required: ["a", "b"],
      type: "object"
    },
    name: "add"
  },
  %{
    description: "A tool that fails",
    inputSchema: %{properties: %{}, type: "object"},
    name: "fail_tool"
  },
  %{
    annotations: %{destructiveHint: false, readOnlyHint: true},
    description: "List all items",
    inputSchema: %{properties: %{}, type: "object"},
    name: "list_items"
  },
  %{
    annotations: %{
      destructiveHint: true,
      idempotentHint: true,
      readOnlyHint: false
    },
    description: "Delete an item",
    inputSchema: %{
      properties: %{"id" => %{description: "Item ID", type: "string"}},
      required: ["id"],
      type: "object"
    },
    name: "delete_item"
  },
  %{
    description: "Get current weather",
    inputSchema: %{
      properties: %{"city" => %{description: "City name", type: "string"}},
      required: ["city"],
      type: "object"
    },
    name: "get_weather",
    outputSchema: %{
      properties: %{
        conditions: %{description: "Weather conditions", type: "string"},
        temperature: %{description: "Temperature in celsius", type: "number"}
      },
      required: ["temperature", "conditions"],
      type: "object"
    }
  },
  %{
    annotations: %{destructiveHint: false, readOnlyHint: true},
    description: "Read the audit log",
    inputSchema: %{properties: %{}, type: "object"},
    name: "audit_log",
    outputSchema: %{
      properties: %{entries: %{items: %{type: "object"}, type: "array"}},
      required: ["entries"],
      type: "object"
    }
  }
]
