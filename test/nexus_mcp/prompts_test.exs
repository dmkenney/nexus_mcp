defmodule NexusMCP.PromptsTest do
  use ExUnit.Case

  import NexusMCP.TestHelpers

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
    test "advertises prompts capability when server defines prompts" do
      {_id, pid} = start_session(NexusMCP.TestServerPrompts)
      result = initialize(pid)

      assert get_in(result, ["result", "capabilities", "prompts"]) == %{"listChanged" => false}
    end

    test "does not advertise prompts when none defined" do
      {_id, pid} = start_session(NexusMCP.TestServer)
      result = initialize(pid)

      refute Map.has_key?(result["result"]["capabilities"], "prompts")
    end
  end

  describe "prompts/list" do
    test "returns all defined prompts" do
      pid = init()

      result = Session.rpc(pid, %{method: "prompts/list", id: 1, params: %{}})
      assert %{"result" => %{"prompts" => prompts}} = result

      names = Enum.map(prompts, & &1.name)
      assert "greet" in names
      assert "summarize" in names
      assert "no_args" in names
    end

    test "each prompt has name, description, and arguments" do
      pid = init()

      result = Session.rpc(pid, %{method: "prompts/list", id: 1, params: %{}})
      greet = Enum.find(result["result"]["prompts"], &(&1.name == "greet"))

      assert greet.description == "Greet someone by name"
      assert greet.arguments == [%{name: "name", description: "Person's name", required: true}]
    end

    test "fails if not initialized" do
      {_id, pid} = start_session(NexusMCP.TestServerPrompts)
      result = Session.rpc(pid, %{method: "prompts/list", id: 1, params: %{}})
      assert %{"error" => %{"code" => -32600}} = result
    end
  end

  describe "prompts/get" do
    test "returns messages for a valid prompt" do
      pid = init()

      result =
        Session.rpc(pid, %{
          method: "prompts/get",
          id: 2,
          params: %{"name" => "greet", "arguments" => %{"name" => "Alice"}}
        })

      assert %{
               "result" => %{
                 "description" => "Greet someone by name",
                 "messages" => [
                   %{
                     role: "user",
                     content: %{type: "text", text: "Say hello to Alice"}
                   }
                 ]
               }
             } = result
    end

    test "optional argument is omitted gracefully" do
      pid = init()

      result =
        Session.rpc(pid, %{
          method: "prompts/get",
          id: 3,
          params: %{"name" => "summarize", "arguments" => %{"text" => "hi"}}
        })

      assert %{"result" => %{"messages" => [%{content: %{text: text}}]}} = result
      assert text =~ "Summarize in 100 words or fewer:"
    end

    test "missing required argument returns -32602" do
      pid = init()

      result =
        Session.rpc(pid, %{
          method: "prompts/get",
          id: 4,
          params: %{"name" => "greet", "arguments" => %{}}
        })

      assert %{"error" => %{"code" => -32602, "message" => msg}} = result
      assert msg =~ "name"
    end

    test "unknown prompt returns -32602" do
      pid = init()

      result =
        Session.rpc(pid, %{
          method: "prompts/get",
          id: 5,
          params: %{"name" => "nope", "arguments" => %{}}
        })

      assert %{"error" => %{"code" => -32602}} = result
    end

    test "session is bound in handler body" do
      pid = init()

      result =
        Session.rpc(pid, %{
          method: "prompts/get",
          id: 6,
          params: %{"name" => "see_session", "arguments" => %{}}
        })

      assert %{"result" => %{"messages" => [%{content: %{text: text}}]}} = result
      assert text =~ "session: "
    end

    test "fails if not initialized" do
      {_id, pid} = start_session(NexusMCP.TestServerPrompts)

      result =
        Session.rpc(pid, %{
          method: "prompts/get",
          id: 1,
          params: %{"name" => "greet", "arguments" => %{"name" => "X"}}
        })

      assert %{"error" => %{"code" => -32600}} = result
    end
  end

  describe "Server.Prompt.build_arguments/1" do
    test "marks required and propagates description" do
      args =
        NexusMCP.Server.Prompt.build_arguments(
          a: {:string!, "A field"},
          b: :integer,
          c: {:boolean, "C field"}
        )

      assert args == [
               %{name: "a", required: true, description: "A field"},
               %{name: "b", required: false},
               %{name: "c", required: false, description: "C field"}
             ]
    end
  end
end
