# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## v0.7.0

### Added

- Tool modules: `use NexusMCP.Tools` declares tools outside the server module,
  and `use NexusMCP.Server, tools: [...]` lists them. `tools/0` returns the
  server's own tools, then each module's in list order, and calls are
  dispatched to the declaring module. `wrap_tool_call/2`, `tool_visible?/2`,
  structured output and custom `handle_tool_call/3` overrides that call
  `__nexus_handle_tool_call__/3` work unchanged.
- Duplicate tool names (across the server and its modules) and modules in
  `tools:` that don't `use NexusMCP.Tools` are compile errors in the server.
  Combining `tools:` with a manual `tools/0` is also a compile error.
- Module-level tool defaults: `params:`, `meta:` and `annotations:` on
  `use NexusMCP.Tools` and `use NexusMCP.Server`. Default params come before a
  tool's own, can be replaced by redeclaring the key, and can be dropped per
  tool with `skip_default_params: [...]`. `meta` is merged recursively and
  `annotations` shallowly, the tool's values winning in both.
- Tool and param descriptions may be any expression evaluated at compile time
  (module attributes, function calls, heredocs, `File.read!` with
  `@external_resource`). A non-string description is a compile error with the
  `deftool`'s file and line.

### Notes

- The server reads its tools modules at compile time, as it does its own
  `deftool`s: `tools/0` is a fixed list and dispatch is one function clause
  per tool name. The server has a compile-time dependency on each listed
  module and recompiles when one changes.
- `tools/list` output of servers that don't use the new options is unchanged.
- `deftool` handler clauses are now defined as `__nexus_tool_call__/3`, with
  `__nexus_handle_tool_call__/3` generated in `@before_compile`. Calling
  `__nexus_handle_tool_call__/3` works as before.

### Follow-up

- Prompts and resources still have to be declared in the server module. The
  same module split for `defprompt` and `defresource` is a possible follow-up.

## v0.6.0

### Added

- Optional `tool_visible?/2` server callback for per-session tool visibility.
  Tools it rejects are left out of `tools/list`, and calling one returns the
  unknown-tool response without running `wrap_tool_call/2` or the handler.
  Defaults to `true`, so existing servers are unaffected.
- `meta:` option on `deftool` for server-side tool data, such as tags for
  `tool_visible?/2`. It is stored on the tool definition and stripped from
  `tools/list`.

### Changed

- Calling an unknown tool on a server whose handlers come from `deftool` now
  returns a tool error (`isError: true`, text `Unknown tool: "name"`) instead
  of crashing the task and returning a JSON-RPC internal error.

## v0.5.0

### Added

- Tool output schemas via `deftool`'s `output_schema:` option, advertised as
  `outputSchema` in `tools/list`.
- Structured tool results in the `structuredContent` field of `tools/call`, with
  the serialized JSON still returned in a text content block for backwards
  compatibility.

### Changed

**Declaring an `output_schema` now constrains what a tool may return.** MCP
2025-11-25 requires that a server providing an output schema MUST return
structured results conforming to it, and restricts those schemas to
`type: "object"` at the root. Two rules are now enforced:

- **The schema's root type must be `"object"`.** Declaring an array or scalar
  root type raises `ArgumentError` where the tool is defined, rather than
  advertising a shape `structuredContent` cannot carry. To return a list, wrap
  it:

  ```elixir
  # Before — no longer valid
  output_schema: %{type: "array", items: %{type: "object"}}

  # After
  output_schema: %{
    type: "object",
    properties: %{entries: %{type: "array", items: %{type: "object"}}},
    required: ["entries"]
  }
  ```

- **A tool declaring a schema must return a map.** A list, a scalar, or
  pre-formatted content blocks cannot conform, so they now produce a tool
  execution error (`isError: true`) instead of a successful response silently
  missing the `structuredContent` the tool advertised. Unstructured content may
  accompany a structured result, but cannot replace it.

  Tools that return content blocks directly should omit `output_schema`.

Tools that declare no output schema are unaffected — every return shape that
worked in 0.4.x still works.

### Fixed

- The README installation snippet recommended `~> 0.4.0`, which excludes 0.5.x.

## v0.4.0

### Added

- Idle sessions hibernate after `hibernate_after` (default 60s), substantially
  reducing memory held by long-lived idle sessions. Set to `:infinity` to
  disable.

## v0.3.1

### Added

- CI workflow covering the oldest and current supported toolchains.

### Fixed

- Session RPC no longer crashes the request when it reaches a downed node in a
  distributed registry.

## v0.3.0

### Added

- Prompts primitive: `defprompt`, `prompts/list`, `prompts/get`.
- Resources primitive: `defresource`, `defresource_template`, `resources/list`,
  `resources/templates/list`, `resources/read`.

## v0.2.0

### Added

- Tool annotations support in `deftool`.

### Fixed

- MCP spec compliance: origin validation, protocol version negotiation, and HTTP
  status codes.
