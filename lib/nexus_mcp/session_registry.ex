defmodule NexusMCP.SessionRegistry do
  @moduledoc """
  Behaviour for session registry implementations.

  The default implementation (`NexusMCP.SessionRegistry.Local`) wraps Elixir's
  built-in `Registry` for single-node usage.

  For multi-node deployments, implement this behaviour with `:global`, `:pg`,
  Horde, or your preferred distributed registry.

  ## Configuration

      config :nexus_mcp, registry: MyApp.DistributedRegistry
  """

  @callback register(session_id :: String.t(), pid()) :: :ok | {:error, :already_registered}
  @callback lookup(session_id :: String.t()) :: {:ok, pid()} | :error
  @callback unregister(session_id :: String.t()) :: :ok

  @doc """
  Returns the configured registry module.
  """
  def impl do
    Application.get_env(:nexus_mcp, :registry, NexusMCP.SessionRegistry.Local)
  end
end
