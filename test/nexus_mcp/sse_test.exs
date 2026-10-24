defmodule NexusMCP.SSETest do
  use ExUnit.Case

  import NexusMCP.TestHelpers, only: [start_session: 0]
  import Plug.Test

  alias NexusMCP.SSE

  setup do
    start_supervised!({NexusMCP.Supervisor, []})
    :ok
  end

  test "ends the stream when the connection handler is told to exit" do
    {_session_id, session} = start_session()
    test = self()

    # Stands in for the web server's connection handler, which traps exits and runs the plug in its own process.
    handler =
      spawn(fn ->
        Process.flag(:trap_exit, true)
        send(test, :trapping)
        SSE.start_stream(conn(:get, "/"), session)
        send(test, :stream_ended)
      end)

    assert_receive :trapping
    Process.exit(handler, :shutdown)

    assert_receive :stream_ended, 1_000
  end
end
