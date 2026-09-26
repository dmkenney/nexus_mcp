defmodule NexusMCP.ToolsListCompatTest do
  use ExUnit.Case, async: true

  # test/fixtures/tools_v0.6 holds the tools/0 result of each test server as
  # built by nexus_mcp 0.6.0. Servers that don't use 0.7 features must return
  # equal terms, so tools/list encodes to the same JSON bytes.
  #
  # Terms are compared rather than JSON strings: on OTP 26+ the key order of a
  # small map with atom keys follows the VM's atom table, so the JSON bytes of
  # one term can differ between VMs.
  @fixtures Path.expand("../fixtures/tools_v0.6", __DIR__)

  for path <- Path.wildcard(Path.join(@fixtures, "*.exs")) do
    @external_resource path
    module = Module.concat([Path.basename(path, ".exs")])

    test "#{inspect(module)} tools/0 is unchanged from 0.6" do
      {expected, _binding} = Code.eval_file(unquote(path))
      tools = unquote(module).tools()

      assert tools == expected

      encode = &Jason.encode!(%{"tools" => Enum.map(&1, fn tool -> Map.delete(tool, :meta) end)})
      assert encode.(tools) == encode.(expected)
    end
  end
end
