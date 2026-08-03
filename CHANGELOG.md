# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
