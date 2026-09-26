[
  %{
    description: "Visible to everyone",
    inputSchema: %{properties: %{}, type: "object"},
    name: "public_tool"
  },
  %{
    description: "Visible to admins only",
    inputSchema: %{properties: %{}, type: "object"},
    meta: %{admin: true},
    name: "admin_tool"
  },
  %{
    description: "Structured admin report",
    inputSchema: %{properties: %{}, type: "object"},
    meta: %{admin: true},
    name: "admin_report",
    outputSchema: %{
      properties: %{count: %{type: "integer"}},
      required: ["count"],
      type: "object"
    }
  }
]
