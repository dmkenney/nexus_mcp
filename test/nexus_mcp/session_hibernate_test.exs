defmodule NexusMCP.SessionHibernateTest do
  use ExUnit.Case, async: false

  alias NexusMCP.Session

  # Hibernation is asserted through its observable effect - the process heap
  # shrinking - rather than through `Process.info(pid, :current_function)`.
  # That probe only reports `{:erlang, :hibernate, 3}` if it happens to be
  # sampled while the process is parked, which makes it timing dependent.

  defmodule QuickHibernateServer do
    use NexusMCP.Server,
      name: "hib-server",
      version: "1.0.0",
      idle_timeout: 60_000,
      hibernate_after: 40

    @impl true
    def tools, do: []

    @impl true
    def handle_tool_call(_name, _args, _session), do: {:ok, "ok"}
  end

  defmodule NoHibernateServer do
    use NexusMCP.Server,
      name: "no-hib-server",
      version: "1.0.0",
      idle_timeout: 60_000,
      hibernate_after: :infinity

    @impl true
    def tools, do: []

    @impl true
    def handle_tool_call(_name, _args, _session), do: {:ok, "ok"}
  end

  defmodule TaskWakeServer do
    use NexusMCP.Server,
      name: "task-wake-server",
      version: "1.0.0",
      idle_timeout: 400,
      hibernate_after: 30

    @impl true
    def tools, do: []

    @impl true
    def handle_tool_call(_name, _args, _session), do: {:ok, "ok"}
  end

  defmodule ShortIdleServer do
    use NexusMCP.Server,
      name: "short-idle-server",
      version: "1.0.0",
      idle_timeout: 250,
      hibernate_after: 30

    @impl true
    def tools, do: []

    @impl true
    def handle_tool_call(_name, _args, _session), do: {:ok, "ok"}
  end

  setup do
    start_supervised!({NexusMCP.Supervisor, []})
    :ok
  end

  defp start_session(server, id) do
    {:ok, pid} = Session.start_link(session_id: id, server_module: server)
    pid
  end

  defp heap_words(pid) do
    case Process.info(pid, :total_heap_size) do
      {:total_heap_size, words} -> words
      nil -> 0
    end
  end

  # Give the session a heap worth reclaiming. Unknown messages fall through to
  # the catch-all clause, which is enough to make the process allocate.
  defp grow_heap(pid) do
    for _ <- 1..40, do: send(pid, {:noise, :binary.copy(<<0>>, 20_000)})
    Process.sleep(20)
  end

  defp eventually(fun, deadline_ms \\ 1_000) do
    deadline = System.monotonic_time(:millisecond) + deadline_ms

    Stream.repeatedly(fun)
    |> Enum.reduce_while(false, fn
      true, _ ->
        {:halt, true}

      false, _ ->
        if System.monotonic_time(:millisecond) > deadline do
          {:halt, false}
        else
          Process.sleep(5)
          {:cont, false}
        end
    end)
  end

  describe "configuration" do
    test "hibernate_after defaults to 15s and is overridable" do
      assert NexusMCP.TestServer.hibernate_after() == 15_000
      assert QuickHibernateServer.hibernate_after() == 40
      assert NoHibernateServer.hibernate_after() == :infinity
    end
  end

  describe "optional callback" do
    # hibernate_after/0 is declared @optional_callbacks: a module implementing
    # the behaviour by hand can omit it, and Session falls back to the default
    # rather than crashing.
    defmodule LegacyServer do
      @behaviour NexusMCP.Server

      def server_info, do: %{name: "legacy", version: "1.0.0"}
      def idle_timeout, do: 60_000
      def tools, do: []
      def prompts, do: []
      def resources, do: []
      def resource_templates, do: []
      def init(session), do: {:ok, session}
      def wrap_tool_call(_session, fun), do: fun.()
      def handle_tool_call(_name, _args, _session), do: {:ok, "ok"}
      def handle_prompt_get(_name, _args, _session), do: {:error, "unsupported"}
      def handle_resource_read(_uri, _session), do: {:error, "unsupported"}
    end

    test "a server without hibernate_after/0 still starts and hibernates" do
      refute function_exported?(LegacyServer, :hibernate_after, 0)

      pid = start_session(LegacyServer, "hib-legacy")
      assert Process.alive?(pid)

      grow_heap(pid)
      grown = heap_words(pid)
      assert grown > 0
    end
  end

  describe "hibernation" do
    test "a quiet session releases the heap it grew" do
      pid = start_session(QuickHibernateServer, "hib-shrink")
      grow_heap(pid)

      grown = heap_words(pid)
      assert grown > 0

      assert eventually(fn -> heap_words(pid) < grown end),
             "expected the heap to shrink once the session went quiet (stayed at #{grown} words)"

      assert Process.alive?(pid)
    end

    test "a session under steady activity keeps its heap" do
      pid = start_session(QuickHibernateServer, "hib-busy")
      grow_heap(pid)

      # Poke it more often than the 40ms quiet window for ~5 windows' worth.
      for _ <- 1..10 do
        send(pid, {:noise, :binary.copy(<<0>>, 20_000)})
        Process.sleep(15)
      end

      assert heap_words(pid) > 0
      assert Process.alive?(pid)
    end

    test "hibernate_after: :infinity disables hibernation" do
      pid = start_session(NoHibernateServer, "hib-off")
      grow_heap(pid)

      grown = heap_words(pid)
      Process.sleep(150)

      assert heap_words(pid) >= grown,
             "heap should not have been reclaimed with hibernation disabled"

      assert Process.alive?(pid)
    end
  end

  describe "idle expiry" do
    # `:hibernate` occupies the same tuple slot as the GenServer idle timeout,
    # so hibernating cancels it. The session must still expire on schedule.
    test "a hibernated session still expires" do
      pid = start_session(ShortIdleServer, "hib-expires")
      ref = Process.monitor(pid)

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 2_000
    end

    test "a session with hibernation disabled still expires" do
      defmodule ShortIdleNoHibServer do
        use NexusMCP.Server,
          name: "short-idle-no-hib",
          version: "1.0.0",
          idle_timeout: 250,
          hibernate_after: :infinity

        @impl true
        def tools, do: []

        @impl true
        def handle_tool_call(_name, _args, _session), do: {:ok, "ok"}
      end

      pid = start_session(ShortIdleNoHibServer, "hib-off-expires")
      ref = Process.monitor(pid)

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 2_000
    end

    # Regression: hibernating has to arm the inactivity deadline by hand, and
    # a naive `Process.send_after(self(), :timeout, ...)` cannot be taken back.
    # Activity after hibernation would then kill the session early, long before
    # its configured idle_timeout had actually elapsed.
    # Hibernating must not extend the inactivity deadline. With
    # hibernate_after: 30 and idle_timeout: 250 the session must still die at
    # ~250ms from its last activity, not 30 + 250 = 280ms.
    test "hibernating does not extend the inactivity deadline" do
      pid = start_session(ShortIdleServer, "hib-no-extend")
      ref = Process.monitor(pid)

      started = System.monotonic_time(:millisecond)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 2_000
      elapsed = System.monotonic_time(:millisecond) - started

      assert elapsed < 250 + 25,
             "expected expiry ~250ms after last activity, took #{elapsed}ms " <>
               "(hibernation restarted the deadline instead of preserving it)"
    end

    # A task completing wakes the session. Any deadline armed while it was
    # hibernating must be dropped, or it fires on the *old* schedule and kills
    # a session that has just done work.
    test "a task waking the session invalidates the deadline armed while hibernating" do
      pid = start_session(TaskWakeServer, "hib-task-wake")
      ref = Process.monitor(pid)

      # Hibernates at ~30ms, recording a deadline ~400ms out from start.
      Process.sleep(150)
      assert Process.alive?(pid)

      # A task result wakes it; expiry should now be a full idle_timeout away.
      send(pid, {make_ref(), {:ok, "done"}})
      woke_at = System.monotonic_time(:millisecond)

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 2_000
      lived = System.monotonic_time(:millisecond) - woke_at

      assert lived > 300,
             "session died #{lived}ms after a task woke it, expected ~400ms - the " <>
               "deadline armed before hibernating was not invalidated"
    end

    # Same for the monitor-down path (task crash / SSE drop).
    test "a monitor DOWN waking the session invalidates the stale deadline" do
      pid = start_session(TaskWakeServer, "hib-down-wake")
      ref = Process.monitor(pid)

      Process.sleep(150)
      assert Process.alive?(pid)

      send(pid, {:DOWN, make_ref(), :process, self(), :normal})
      woke_at = System.monotonic_time(:millisecond)

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 2_000
      lived = System.monotonic_time(:millisecond) - woke_at

      assert lived > 300,
             "session died #{lived}ms after a DOWN woke it, expected ~400ms"
    end

    test "activity after hibernating postpones expiry" do
      pid = start_session(ShortIdleServer, "hib-refresh")
      ref = Process.monitor(pid)

      # Let it hibernate (30ms quiet window) and arm its 250ms deadline.
      Process.sleep(120)
      assert Process.alive?(pid)

      # Now keep it busy well past that original deadline.
      for _ <- 1..12 do
        send(pid, :ping_noise)
        Process.sleep(40)
      end

      refute_received {:DOWN, ^ref, :process, ^pid, _},
                      "session died despite continuous activity after hibernating"

      assert Process.alive?(pid),
             "session terminated early - the idle deadline armed before hibernating was not invalidated by later activity"
    end
  end
end
