defmodule NexusMCP.Server.ToolDefaultsTest do
  use ExUnit.Case, async: true

  defp tool(module, name), do: Enum.find(module.__nexus_tools__(), &(&1.name == name))

  describe "default params" do
    test "are added before the tool's own params" do
      schema = tool(NexusMCP.TestTools.Pages, "get_page").inputSchema

      assert schema.properties == %{
               "account_id" => %{
                 type: "string",
                 description: "Account ID (use list_accounts to find)"
               },
               "site" => %{type: "string", description: "Site slug"},
               "id" => %{type: "string", description: "Page ID"}
             }

      assert schema.required == ["account_id", "id"]
    end

    test "can be overridden by declaring the same key" do
      schema = tool(NexusMCP.TestTools.Pages, "search_pages").inputSchema

      assert schema.properties["account_id"] == %{
               type: "string",
               description: "Account ID, defaults to all"
             }

      assert schema.required == ["q"]
    end

    test "can be skipped" do
      schema = tool(NexusMCP.TestTools.Pages, "list_accounts").inputSchema
      assert schema == %{type: "object", properties: %{}}
    end

    test "skipping a param that is not a default raises" do
      assert_raise CompileError, ~r/skips \[:nope\] in skip_default_params/, fn ->
        Code.compile_string("""
        defmodule NexusMCP.ToolDefaultsTest.BadSkip do
          use NexusMCP.Tools, params: [account_id: :string!]

          deftool "t", "T", params: [], skip_default_params: [:nope] do
            {:ok, nil}
          end
        end
        """)
      end
    end
  end

  describe "default annotations" do
    test "apply to tools without annotations" do
      assert tool(NexusMCP.TestTools.Pages, "get_page").annotations == %{readOnlyHint: true}
    end

    test "merge with the tool's annotations, the tool winning" do
      assert tool(NexusMCP.TestTools.Pages, "rename_page").annotations == %{
               readOnlyHint: false,
               title: "Rename page"
             }
    end
  end

  describe "server module defaults" do
    test "apply to the server's own deftools" do
      [{module, _}] =
        Code.compile_string("""
        defmodule NexusMCP.ToolDefaultsTest.Server do
          use NexusMCP.Server,
            name: "defaults",
            version: "1.0.0",
            params: [account_id: {:string!, "Account"}],
            meta: %{admin: true}

          deftool "t", "T", params: [id: :string] do
            {:ok, params}
          end
        end
        """)

      [t] = module.tools()
      assert t.inputSchema.required == ["account_id"]
      assert Map.keys(t.inputSchema.properties) == ["account_id", "id"]
      assert t.meta == %{admin: true}
    end
  end

  describe "non-literal descriptions" do
    test "come from a module attribute, a function call, a file and a heredoc" do
      mod = NexusMCP.TestTools.Descriptions

      attr = tool(mod, "attr_desc")
      assert attr.description == "From an attribute"
      assert attr.inputSchema.properties["x"].description == "From an attribute"

      call = tool(mod, "call_desc")
      assert call.description == "From a call"

      assert call.inputSchema.properties["x"] == %{
               type: "array",
               items: %{type: "string"},
               description: "SHOUT"
             }

      assert tool(mod, "file_desc").description == "Guide read from a file.\n"

      heredoc = tool(mod, "heredoc_desc")
      assert heredoc.description == "From a heredoc.\nSecond line.\n"
      assert heredoc.inputSchema.properties["x"].description == "Param heredoc.\n"
    end

    test "a non-string tool description raises at compile time" do
      {error, warnings} =
        ExUnit.CaptureIO.with_io(:stderr, fn ->
          assert_raise CompileError, fn ->
            Code.compile_string(
              """
              defmodule NexusMCP.ToolDefaultsTest.BadDescription do
                use NexusMCP.Tools

                deftool "bad", @missing, params: [] do
                  {:ok, nil}
                end
              end
              """,
              "bad_description.ex"
            )
          end
        end)

      assert warnings =~ "undefined module attribute @missing"
      assert error.file =~ "bad_description.ex"
      assert error.line == 4

      assert error.description =~
               ~s(description of tool "bad" must evaluate to a string, got: nil)
    end

    test "a non-string param description raises at compile time" do
      error =
        assert_raise CompileError, fn ->
          Code.compile_string(
            """
            defmodule NexusMCP.ToolDefaultsTest.BadParamDescription do
              use NexusMCP.Tools

              deftool "bad", "Bad", params: [id: {:string!, 42}] do
                {:ok, nil}
              end
            end
            """,
            "bad_param.ex"
          )
        end

      assert error.line == 4

      assert error.description =~
               ~s(tool "bad": param :id: param description must evaluate to a string, got: 42)
    end
  end
end
