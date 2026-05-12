defmodule NexusMCP.TestServerPrompts do
  @moduledoc false

  use NexusMCP.Server,
    name: "test-server-prompts",
    version: "1.0.0"

  # --- Prompts ---

  defprompt "greet", "Greet someone by name", arguments: [name: {:string!, "Person's name"}] do
    {:ok,
     [
       %{
         role: "user",
         content: %{type: "text", text: "Say hello to " <> params["name"]}
       }
     ]}
  end

  defprompt "summarize", "Summarize some text",
    arguments: [
      text: {:string!, "Text to summarize"},
      max_words: {:integer, "Word cap"}
    ] do
    cap = Map.get(params, "max_words", 100)

    {:ok,
     [
       %{
         role: "user",
         content: %{
           type: "text",
           text: "Summarize in #{cap} words or fewer:\n" <> params["text"]
         }
       }
     ]}
  end

  defprompt "no_args", "A prompt that takes no arguments", arguments: [] do
    {:ok, [%{role: "user", content: %{type: "text", text: "hello"}}]}
  end

  defprompt "see_session", "Return the session id in a message", arguments: [] do
    {:ok,
     [
       %{
         role: "user",
         content: %{type: "text", text: "session: " <> session.session_id}
       }
     ]}
  end

  # --- Resources ---

  defresource "config://app",
    name: "app_config",
    description: "App config",
    mime_type: "application/json" do
    {:ok, Jason.encode!(%{theme: "dark"})}
  end

  defresource "binary://logo",
    name: "logo",
    mime_type: "image/png" do
    {:ok, <<137, 80, 78, 71>>}
  end

  defresource "manual://shape",
    name: "manual_shape",
    description: "Returns a pre-shaped contents map",
    mime_type: "text/plain" do
    {:ok, %{text: "pre-shaped"}}
  end

  # --- Resource templates ---

  defresource_template "doc:///{slug}",
    name: "doc_by_slug",
    description: "Document looked up by slug",
    mime_type: "text/markdown" do
    {:ok, "# Doc: " <> params["slug"]}
  end

  defresource_template "tree:///{+path}",
    name: "tree_path",
    description: "Multi-segment path",
    mime_type: "text/plain" do
    {:ok, "path was: " <> params["path"]}
  end
end
