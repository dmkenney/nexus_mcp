defmodule NexusMCP.Supervisor do
  @moduledoc """
  Supervision tree for NexusMCP.

  Starts:
  - `Registry` — for local session lookup
  - `DynamicSupervisor` — starts/stops session GenServers
  - `Task.Supervisor` — concurrent tool execution

  ## Usage

      children = [
        {NexusMCP.Supervisor, []},
        ...
      ]
  """

  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      {Registry, keys: :unique, name: NexusMCP.Registry},
      {DynamicSupervisor, name: NexusMCP.SessionSupervisor, strategy: :one_for_one},
      {Task.Supervisor, name: NexusMCP.TaskSupervisor}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
