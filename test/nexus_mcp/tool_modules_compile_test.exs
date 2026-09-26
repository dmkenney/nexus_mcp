defmodule NexusMCP.ToolModulesCompileTest do
  use ExUnit.Case, async: true

  defp compile_error(code) do
    assert_raise CompileError, fn -> Code.compile_string(code, "tool_modules_test.ex") end
  end

  defp unique, do: "M#{System.unique_integer([:positive])}"

  test "a tool name declared in two modules raises" do
    m = unique()

    error =
      compile_error("""
      defmodule #{m}.A do
        use NexusMCP.Tools

        deftool "dup", "A", params: [] do
          {:ok, 1}
        end
      end

      defmodule #{m}.B do
        use NexusMCP.Tools

        deftool "dup", "B", params: [] do
          {:ok, 2}
        end
      end

      defmodule #{m}.Server do
        use NexusMCP.Server, name: "x", version: "1", tools: [#{m}.A, #{m}.B]
      end
      """)

    assert error.file =~ "tool_modules_test.ex"
    assert error.line == 12
    assert error.description =~ ~s(tool "dup" is declared more than once: in #{m}.A)
    assert error.description =~ "and in #{m}.B"
  end

  test "a tool name declared in the server and a module raises" do
    m = unique()

    error =
      compile_error("""
      defmodule #{m}.A do
        use NexusMCP.Tools

        deftool "dup", "A", params: [] do
          {:ok, 1}
        end
      end

      defmodule #{m}.Server do
        use NexusMCP.Server, name: "x", version: "1", tools: [#{m}.A]

        deftool "dup", "Server", params: [] do
          {:ok, 2}
        end
      end
      """)

    assert error.line == 4
    assert error.description =~ ~s(tool "dup" is declared more than once: in #{m}.Server)
  end

  test "a tool name declared twice in one module raises" do
    assert_raise CompileError, ~r/"dup" is declared more than once/, fn ->
      Code.compile_string("""
      defmodule #{unique()} do
        use NexusMCP.Tools

        deftool "dup", "A", params: [] do
          {:ok, 1}
        end

        deftool "dup", "B", params: [] do
          {:ok, 2}
        end
      end
      """)
    end
  end

  test "a module in tools: that does not use NexusMCP.Tools raises" do
    m = unique()

    error =
      compile_error("""
      defmodule #{m}.NotTools do
        def hello, do: :world
      end

      defmodule #{m}.Server do
        use NexusMCP.Server, name: "x", version: "1", tools: [#{m}.NotTools]
      end
      """)

    assert error.line == 6
    assert error.description =~ "#{m}.NotTools is listed in tools:"
    assert error.description =~ "does not use NexusMCP.Tools"
  end

  test "tools: with a manual tools/0 raises" do
    m = unique()

    error =
      assert_raise CompileError, fn ->
        Code.compile_string("""
        defmodule #{m}.A do
          use NexusMCP.Tools
        end

        defmodule #{m}.Server do
          use NexusMCP.Server, name: "x", version: "1", tools: [#{m}.A]

          def tools, do: []
        end
        """)
      end

    assert error.line == 6
    assert error.description =~ "lists tools: modules and defines a manual tools/0"
  end

  test "deftool with a manual tools/0 still raises" do
    assert_raise CompileError, ~r/defines both deftool and a manual tools\/0/, fn ->
      Code.compile_string("""
      defmodule #{unique()} do
        use NexusMCP.Server, name: "x", version: "1"

        deftool "t", "T", params: [] do
          {:ok, 1}
        end

        def tools, do: []
      end
      """)
    end
  end

  test "unknown use NexusMCP.Tools options raise" do
    assert_raise CompileError, ~r/unknown options for use NexusMCP.Tools: \[:parms\]/, fn ->
      Code.compile_string("""
      defmodule #{unique()} do
        use NexusMCP.Tools, parms: []
      end
      """)
    end
  end
end
