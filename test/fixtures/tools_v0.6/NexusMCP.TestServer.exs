[
  %{
    description: "Echo back the input",
    inputSchema: %{
      properties: %{"message" => %{type: "string"}},
      type: "object"
    },
    name: "echo"
  },
  %{
    description: "A slow tool for testing concurrency",
    inputSchema: %{
      properties: %{"delay_ms" => %{type: "integer"}},
      type: "object"
    },
    name: "slow_tool"
  },
  %{
    description: "A tool that always fails",
    inputSchema: %{properties: %{}, type: "object"},
    name: "failing_tool"
  },
  %{
    description: "A tool that crashes",
    inputSchema: %{properties: %{}, type: "object"},
    name: "crash_tool"
  },
  %{
    description: "Returns a map result",
    inputSchema: %{properties: %{}, type: "object"},
    name: "map_result"
  },
  %{
    description: "Returns a list of content items",
    inputSchema: %{properties: %{}, type: "object"},
    name: "list_result"
  },
  %{
    description: "Returns the session assigns",
    inputSchema: %{properties: %{}, type: "object"},
    name: "check_assigns"
  },
  %{
    description: "Returns a list of plain maps (like list_pages)",
    inputSchema: %{properties: %{}, type: "object"},
    name: "list_of_maps"
  },
  %{
    description: "Returns atom-keyed content items",
    inputSchema: %{properties: %{}, type: "object"},
    name: "list_atom_content"
  },
  %{
    description: "Returns an empty list",
    inputSchema: %{properties: %{}, type: "object"},
    name: "empty_list"
  },
  %{
    description: "Returns a map and declares an output schema",
    inputSchema: %{properties: %{}, type: "object"},
    name: "structured_map",
    outputSchema: %{
      properties: %{"temperature" => %{type: "number"}},
      required: ["temperature"],
      type: "object"
    }
  },
  %{
    description: "Returns a bare list despite declaring an output schema",
    inputSchema: %{properties: %{}, type: "object"},
    name: "structured_list",
    outputSchema: %{
      properties: %{entries: %{items: %{type: "object"}, type: "array"}},
      required: ["entries"],
      type: "object"
    }
  },
  %{
    description: "Declares an output schema but returns an error",
    inputSchema: %{properties: %{}, type: "object"},
    name: "structured_failing",
    outputSchema: %{type: "object"}
  },
  %{
    description: "Declares an output schema but returns content items",
    inputSchema: %{properties: %{}, type: "object"},
    name: "structured_content_items",
    outputSchema: %{type: "object"}
  }
]
