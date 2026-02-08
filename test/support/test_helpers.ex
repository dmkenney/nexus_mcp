defmodule NexusMCP.TestHelpers do
  @moduledoc false

  alias NexusMCP.Session

  @doc """
  Starts a session under the DynamicSupervisor with a random ID.
  Returns `{session_id, pid}`.
  """
  def start_session(server_module \\ NexusMCP.TestServer, assigns \\ %{}) do
    session_id = random_session_id()

    {:ok, pid} =
      DynamicSupervisor.start_child(
        NexusMCP.SessionSupervisor,
        {Session, [session_id: session_id, server_module: server_module, assigns: assigns]}
      )

    {session_id, pid}
  end

  @doc """
  Sends an initialize RPC to the given session pid.
  """
  def initialize(pid) do
    Session.rpc(pid, %{
      method: "initialize",
      id: 1,
      params: %{
        "protocolVersion" => "2025-03-26",
        "clientInfo" => %{"name" => "test", "version" => "1.0.0"},
        "capabilities" => %{}
      }
    })
  end

  @doc """
  Polls the registry until the given session ID is no longer registered.
  Raises if cleanup doesn't happen within ~500ms.
  """
  def await_registry_cleanup(session_id, retries \\ 100) do
    registry = NexusMCP.SessionRegistry.impl()

    case registry.lookup(session_id) do
      :error ->
        :ok

      {:ok, _} when retries > 0 ->
        Process.sleep(5)
        await_registry_cleanup(session_id, retries - 1)

      {:ok, _} ->
        raise "Registry did not clean up session #{session_id} in time"
    end
  end

  defp random_session_id do
    :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  end
end
