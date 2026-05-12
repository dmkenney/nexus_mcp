defmodule NexusMCP.ResourcesTest do
  use ExUnit.Case

  import NexusMCP.TestHelpers

  alias NexusMCP.Server.Resource
  alias NexusMCP.Session

  setup do
    start_supervised!({NexusMCP.Supervisor, []})
    :ok
  end

  defp init(server \\ NexusMCP.TestServerPrompts) do
    {_id, pid} = start_session(server)
    initialize(pid)
    pid
  end

  describe "initialize capabilities" do
    test "advertises resources capability when server defines resources or templates" do
      {_id, pid} = start_session(NexusMCP.TestServerPrompts)
      result = initialize(pid)

      assert get_in(result, ["result", "capabilities", "resources"]) ==
               %{"subscribe" => false, "listChanged" => false}
    end

    test "does not advertise resources when none defined" do
      {_id, pid} = start_session(NexusMCP.TestServer)
      result = initialize(pid)

      refute Map.has_key?(result["result"]["capabilities"], "resources")
    end
  end

  describe "resources/list" do
    test "returns static resources only" do
      pid = init()

      result = Session.rpc(pid, %{method: "resources/list", id: 1, params: %{}})
      assert %{"result" => %{"resources" => resources}} = result

      uris = Enum.map(resources, & &1.uri)
      assert "config://app" in uris
      assert "binary://logo" in uris
      refute Enum.any?(uris, &String.contains?(&1, "{"))
    end

    test "fails if not initialized" do
      {_id, pid} = start_session(NexusMCP.TestServerPrompts)
      result = Session.rpc(pid, %{method: "resources/list", id: 1, params: %{}})
      assert %{"error" => %{"code" => -32600}} = result
    end
  end

  describe "resources/templates/list" do
    test "returns templates without internal regex fields" do
      pid = init()

      result = Session.rpc(pid, %{method: "resources/templates/list", id: 1, params: %{}})
      assert %{"result" => %{"resourceTemplates" => templates}} = result

      uris = Enum.map(templates, & &1.uriTemplate)
      assert "doc:///{slug}" in uris
      assert "tree:///{+path}" in uris

      Enum.each(templates, fn t ->
        refute Map.has_key?(t, :__regex__)
        refute Map.has_key?(t, :__vars__)
      end)
    end
  end

  describe "resources/read — static" do
    test "text mime returns text contents" do
      pid = init()

      result =
        Session.rpc(pid, %{
          method: "resources/read",
          id: 2,
          params: %{"uri" => "config://app"}
        })

      assert %{
               "result" => %{
                 "contents" => [
                   %{
                     "uri" => "config://app",
                     "mimeType" => "application/json",
                     "text" => text
                   }
                 ]
               }
             } = result

      assert Jason.decode!(text) == %{"theme" => "dark"}
    end

    test "binary mime base64-encodes as blob" do
      pid = init()

      result =
        Session.rpc(pid, %{
          method: "resources/read",
          id: 3,
          params: %{"uri" => "binary://logo"}
        })

      assert %{
               "result" => %{
                 "contents" => [
                   %{"uri" => "binary://logo", "mimeType" => "image/png", "blob" => blob}
                 ]
               }
             } = result

      assert Base.decode64!(blob) == <<137, 80, 78, 71>>
    end

    test "pre-shaped %{text: ...} return value is passed through" do
      pid = init()

      result =
        Session.rpc(pid, %{
          method: "resources/read",
          id: 4,
          params: %{"uri" => "manual://shape"}
        })

      assert %{"result" => %{"contents" => [%{"text" => "pre-shaped"}]}} = result
    end
  end

  describe "resources/read — templates" do
    test "single-segment template captures path" do
      pid = init()

      result =
        Session.rpc(pid, %{
          method: "resources/read",
          id: 5,
          params: %{"uri" => "doc:///intro"}
        })

      assert %{
               "result" => %{
                 "contents" => [
                   %{
                     "uri" => "doc:///intro",
                     "mimeType" => "text/markdown",
                     "text" => "# Doc: intro"
                   }
                 ]
               }
             } = result
    end

    test "single-segment template rejects multi-segment input" do
      pid = init()

      result =
        Session.rpc(pid, %{
          method: "resources/read",
          id: 6,
          params: %{"uri" => "doc:///deep/path"}
        })

      # doc:/// only matches single segment; falls through to tree:/// or not_found
      assert %{"error" => %{"code" => -32002, "data" => %{"uri" => "doc:///deep/path"}}} = result
    end

    test "reserved-expansion template matches multi-segment" do
      pid = init()

      result =
        Session.rpc(pid, %{
          method: "resources/read",
          id: 7,
          params: %{"uri" => "tree:///a/b/c"}
        })

      assert %{"result" => %{"contents" => [%{"text" => "path was: a/b/c"}]}} = result
    end
  end

  describe "resources/read errors" do
    test "unknown uri returns -32002 with uri in data" do
      pid = init()

      result =
        Session.rpc(pid, %{
          method: "resources/read",
          id: 8,
          params: %{"uri" => "missing://nope"}
        })

      assert %{"error" => %{"code" => -32002, "data" => %{"uri" => "missing://nope"}}} = result
    end

    test "missing uri param returns -32602" do
      pid = init()

      result =
        Session.rpc(pid, %{
          method: "resources/read",
          id: 9,
          params: %{}
        })

      assert %{"error" => %{"code" => -32602}} = result
    end
  end

  describe "Resource.compile_template/1" do
    test "single var becomes single-segment capture" do
      assert {regex, ["path"]} = Resource.compile_template("file:///{path}")
      assert regex == "^file:///(?<path>[^/]+)$"
    end

    test "reserved var becomes greedy capture" do
      assert {regex, ["path"]} = Resource.compile_template("file:///{+path}")
      assert regex == "^file:///(?<path>.+)$"
    end

    test "literal parts are regex-escaped" do
      {regex, []} = Resource.compile_template("foo.bar://baz")
      assert regex == "^foo\\.bar://baz$"
    end
  end

  describe "Resource.match_template/2" do
    test "first match wins; captures keyed by var name" do
      templates = [
        %{__regex__: "^a/(?<x>[^/]+)$", __vars__: ["x"], uriTemplate: "a/{x}"},
        %{__regex__: "^a/(?<y>.+)$", __vars__: ["y"], uriTemplate: "a/{+y}"}
      ]

      assert {:ok, t, %{"x" => "hello"}} = Resource.match_template("a/hello", templates)
      assert t.uriTemplate == "a/{x}"
    end

    test "no match returns :error" do
      assert :error =
               Resource.match_template("nope", [
                 %{__regex__: "^a/(?<x>[^/]+)$", __vars__: ["x"], uriTemplate: "a/{x}"}
               ])
    end
  end
end
