[
  %{
    description: "Check process dictionary",
    inputSchema: %{properties: %{}, type: "object"},
    name: "check_process_dict"
  },
  %{
    description: "Echo for wrap test",
    inputSchema: %{
      properties: %{"message" => %{type: "string"}},
      type: "object"
    },
    name: "echo_wrap"
  }
]
