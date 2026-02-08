defmodule NexusMCP.SessionRegistry.Local do
  @moduledoc """
  Default session registry using Elixir's built-in `Registry`.

  Works out of the box for single-node deployments.
  """

  @behaviour NexusMCP.SessionRegistry

  @registry NexusMCP.Registry

  @impl true
  def register(session_id, pid) do
    case Registry.register(@registry, session_id, pid) do
      {:ok, _} -> :ok
      {:error, {:already_registered, _}} -> {:error, :already_registered}
    end
  end

  @impl true
  def lookup(session_id) do
    case Registry.lookup(@registry, session_id) do
      [{pid, _}] -> {:ok, pid}
      [] -> :error
    end
  end

  @impl true
  def unregister(session_id) do
    Registry.unregister(@registry, session_id)
  end
end
