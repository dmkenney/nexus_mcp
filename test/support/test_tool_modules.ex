defmodule NexusMCP.TestTools.Pages do
  @moduledoc false

  @account_desc "Account ID (use list_accounts to find)"

  use NexusMCP.Tools,
    params: [account_id: {:string!, @account_desc}, site: {:string, "Site slug"}],
    annotations: %{readOnlyHint: true}

  deftool "get_page", "Get a page", params: [id: {:string!, "Page ID"}] do
    {:ok, %{module: "pages", params: params, session_id: session.session_id}}
  end

  deftool "rename_page", "Rename a page",
    params: [id: {:string!, "Page ID"}, title: {:string!, "New title"}],
    annotations: %{readOnlyHint: false, title: "Rename page"} do
    {:ok, %{renamed: params["id"], title: page_title(params)}}
  end

  deftool "list_accounts", "List accounts",
    params: [],
    skip_default_params: [:account_id, :site] do
    {:ok, []}
  end

  deftool "search_pages", "Search pages",
    params: [account_id: {:string, "Account ID, defaults to all"}, q: {:string!, "Query"}] do
    {:ok, []}
  end

  # A helper after the deftools must not split the generated clauses.
  defp page_title(params), do: String.upcase(params["title"])
end

defmodule NexusMCP.TestTools.Admin do
  @moduledoc false

  use NexusMCP.Tools, meta: %{admin: true, tags: %{area: "admin"}}

  deftool "admin_delete_template", "Delete a template",
    params: [id: {:string!, "Template ID"}],
    meta: %{tags: %{danger: true}},
    output_schema: %{
      type: "object",
      properties: %{deleted: %{type: "string"}},
      required: ["deleted"]
    } do
    send(session.assigns.test_pid, {:handle_tool_call, "admin_delete_template"})
    {:ok, %{deleted: params["id"]}}
  end

  deftool "admin_stats", "Admin statistics", params: [], meta: %{admin: false} do
    {:ok, %{module: "admin"}}
  end
end

defmodule NexusMCP.TestServerToolModules do
  @moduledoc false

  use NexusMCP.Server,
    name: "test-tool-modules",
    version: "1.0.0",
    tools: [NexusMCP.TestTools.Pages, NexusMCP.TestTools.Admin]

  @impl true
  def tool_visible?(%{meta: %{admin: true}}, session), do: session.assigns[:admin] == true
  def tool_visible?(_tool, _session), do: true

  @impl true
  def wrap_tool_call(session, fun) do
    if pid = session.assigns[:test_pid], do: send(pid, :wrap_tool_call)
    fun.()
  end

  deftool "server_ping", "Ping the server", params: [] do
    {:ok, %{module: "server", session_id: session.session_id}}
  end
end

defmodule NexusMCP.TestServerToolModulesAuth do
  @moduledoc false

  # Overrides handle_tool_call/3 for per-call auth, then dispatches through
  # the generated __nexus_handle_tool_call__/3.
  use NexusMCP.Server,
    name: "test-tool-modules-auth",
    version: "1.0.0",
    tools: [NexusMCP.TestTools.Pages]

  @impl true
  def handle_tool_call(name, params, session) do
    if session.assigns[:denied] do
      {:error, "denied"}
    else
      __nexus_handle_tool_call__(name, params, session)
    end
  end
end

defmodule NexusMCP.TestTools.Descriptions do
  @moduledoc false

  use NexusMCP.Tools

  @desc "From an attribute"
  @guide_path Path.expand("tool_guide.txt", __DIR__)
  @external_resource @guide_path
  @guide File.read!(@guide_path)

  deftool "attr_desc", @desc, params: [x: {:string!, @desc}] do
    {:ok, params}
  end

  deftool "call_desc", Enum.join(["From", "a", "call"], " "),
    params: [x: {{:array, :string}, String.upcase("shout")}] do
    {:ok, params}
  end

  deftool "file_desc", @guide, params: [] do
    {:ok, params}
  end

  deftool "heredoc_desc",
          """
          From a heredoc.
          Second line.
          """,
          params: [
            x:
              {:integer,
               """
               Param heredoc.
               """}
          ] do
    {:ok, params}
  end
end
