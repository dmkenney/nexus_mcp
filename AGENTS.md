# Nexus MCP

## Project Overview

Elixir library implementing the MCP (Model Context Protocol) Streamable HTTP transport. GenServer-per-session architecture with concurrent tool execution via Task.Supervisor.

## Architecture

- `lib/nexus_mcp/server.ex` — Behaviour module, `use NexusMCP.Server` macro
- `lib/nexus_mcp/server/tool.ex` — `deftool` macro, `@before_compile` hook, `format_changeset_errors/1`
- `lib/nexus_mcp/server/schema.ex` — Param type DSL to JSON Schema conversion
- `lib/nexus_mcp/session.ex` — GenServer per client session, tool dispatch
- `lib/nexus_mcp/transport.ex` — Plug handling POST/GET/DELETE
- `lib/nexus_mcp/sse.ex` — SSE chunked response loop
- `lib/nexus_mcp/session_registry.ex` — Registry behaviour (swappable for distributed)
- `lib/nexus_mcp/supervisor.ex` — Supervision tree (Registry, DynamicSupervisor, Task.Supervisor)

## Development

- Run tests: `mix test`
- Compile: `mix compile`
- Dependencies: `mix deps.get`
- Format: `mix format`
- Build package: `mix hex.build`
- Test support modules live in `test/support/` and are compiled via `elixirc_paths`

## Code Style

- Run `mix format` before committing — CI will reject unformatted code
- Use `@impl true` on all callback implementations
- Atom keys for internal data, string keys for external/serialized data (JSON-RPC, tool params)
- Prefer pattern matching over conditional logic
- Keep modules focused — one responsibility per module
- Use `@doc false` on generated callbacks that users shouldn't call directly

## Testing

- Test support modules go in `test/support/` (loaded via `elixirc_paths(:test)`)
- Shared helpers live in `NexusMCP.TestHelpers` — import rather than duplicating
- Tests that need the supervision tree should `start_supervised!({NexusMCP.Supervisor, []})` in setup
- The `deftool` macro parses `opts, do: block` and `opts do block end` differently — import both arity 3 and 4

## Git

- Do not include AI attribution (e.g. `Co-Authored-By`) in commit messages
- Keep commits focused — one logical change per commit
- Write commit messages that describe the "why", not the "what"
