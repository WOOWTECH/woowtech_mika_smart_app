# Apporo Assistant 0.1.37-apporo.10 alignment

This release takes the shared MCP and skill changes merged for WOOWTECH `woow.10` in PR #27. Apporo retains its own package, release certificate, English-first interface, update channel, and Odoo relay.

## Shared behavior now included

- An MCP server's `allowedTools` filters ordinary tools, `resource_read`, and `prompt_get`. Removing permission, disabling a server, or deleting it blocks the next call with `mcp_tool_not_allowed`. Calls already in progress cannot be recalled.
- The outcome judge sees the names of tools that succeeded. A trial skill is no longer suspended solely because an answer-only judgment failed; a verifier rejection still takes precedence.
- Long MCP results are stored in the current conversation workspace and can be read in chunks through the existing `read_file` tool. The stored result is isolated from other conversations and removed with its workspace.

The shared behavior is covered by the core and App JVM tests added in PR #27. Apporo's release checks also cover its version, package, signing, source contracts, startup, and English runtime. A live model task that revokes an MCP permission mid-run is a separate scenario; these checks do not claim to have exercised it.

The referenced WOOWTECH conversation also concerns a stale link on its Odoo download page. Apporo's `/open-apporo-assistant` page already points to its own `releases/latest` endpoint, so no Apporo web-page change is part of this release.
