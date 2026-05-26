# Changelog

All notable changes to this skill. Format roughly follows [Keep a Changelog](https://keepachangelog.com).

## v1.0.2 — 2026-05-26

First real-world install on a live Hermes Agent 0.14.0 revealed six things the v1.0 skill got wrong. All fixed in this release.

### Changed
- **Composio MCP URL is session-scoped, not static.** The skill previously documented `https://mcp.composio.dev/mcp` as a stable attach URL. The real shape is `https://backend.composio.dev/tool_router/<session_id>/mcp`. `reference/hermes-install.md` now walks through installing the Composio Python SDK on the Hermes host, calling `composio.create(user_id)` once to capture the session ID, and reusing it via `composio.use(session_id)` thereafter.
- **Tool surface is 6 meta-tools, uppercase.** The v1.0 skill described 4 lowercase tools (`composio_search_tools`, `composio_execute_tool`, `composio_multi_execute`, `composio_manage_connections`) derived from the older moltbot Composio plugin README. The real Composio Tool Router on 0.14 exposes 6 uppercase meta-tools: `COMPOSIO_SEARCH_TOOLS`, `COMPOSIO_GET_TOOL_SCHEMAS`, `COMPOSIO_MULTI_EXECUTE_TOOL`, `COMPOSIO_MANAGE_CONNECTIONS`, `COMPOSIO_REMOTE_BASH_TOOL`, `COMPOSIO_REMOTE_WORKBENCH`. There is no standalone single-execute tool — `MULTI_EXECUTE_TOOL` handles single calls via an `executions` list of length 1. `reference/tool-reference.md` rewritten.
- **`hermes mcp add --auth header` only supports Bearer.** Verified in `hermes_cli/mcp_config.py:332-334`. The interactive flow hard-codes `Authorization: Bearer <token>` and cannot accept custom header names. Composio requires `x-api-key`. `reference/hermes-install.md` Path A now uses direct YAML edit of `mcp_servers.composio` instead of the interactive `hermes mcp add` command.
- **Hermes MCP servers stored at top-level `mcp_servers:` in `~/.hermes/config.yaml`.** Not in `state.db`, not in a separate file. Source: `hermes_cli/mcp_config.py:6-9`.
- **Composio v1 REST API deprecated (HTTP 410).** All curl probes now use `/api/v3/...`. `verify_composio.sh` default `BASE_URL` is now `https://backend.composio.dev/api/v3`.
- **Hermes 0.14 has no `hermes config get` subcommand.** Available subcommands: `show`, `edit`, `set`, `path`, `env-path`, `check`, `migrate`. Skill references to `hermes config get ...` replaced with `hermes config show | grep`, or direct YAML reads via Python.

### Added
- `verify_composio.sh` now distinguishes Composio's "DB propagation lag" 401 (code 10401) and 500 (code 809) from genuine auth failures. Says "wait 5 minutes" instead of "rotate the key."
- `verify_composio.sh` handles HTTP 410 explicitly — tells the user to set `COMPOSIO_BASE_URL=https://backend.composio.dev/api/v3` and rerun.
- New error rows in `reference/tool-reference.md` troubleshooting table: DB propagation lag, v1 deprecation.
- Hermes-side SKILL.md workflow now includes an explicit `COMPOSIO_GET_TOOL_SCHEMAS` step between SEARCH_TOOLS and MULTI_EXECUTE_TOOL.
- `assets/hermes-composio-skill/SKILL.md` documents all 6 real tools and the DB-propagation-lag recovery branch.

### Notes
- The v1.0.1 README and 2-tier install flow remain accurate — only the install execution path changed.
- Bootstrap key rotation is still strongly recommended whenever a user pastes a Composio key into a chat session. See `.workflow/.scratchpad/COMPOSIO_KEY_ROTATION_TODO.md` for the procedure.

## v1.0.1 — 2026-05-26

### Changed
- README rewritten with surfer voice + 2-tier install ("paste URL + ask Claude" vs "manual CLI").
- Added "How To Trigger It" section drawing the Claude-Code-installer / Hermes-operator distinction.
- Documented `--no-flair` flag for both helper scripts (plain-English mode).

## v1.0.0 — 2026-05-26

### Added
- Initial release. Claude Code skill that adds Composio (1000+ SaaS tools via OAuth/API key) to a Nous Research Hermes Agent install. Sonnet-tuned tool descriptions, model-router-aware routing (Sonnet primary, Haiku for cheap reads, local Qwen for image prompts), guided API-key onboarding, and a bundled Hermes-side skill asset for installation at `~/.hermes/skills/composio/`.
- 15-field frontmatter (Claude Code v2.1.150) with `model: sonnet` pin.
- MCP (primary) and REST API (fallback) install paths documented.
- 5 reference files: `api-key-setup`, `hermes-install`, `routing-integration`, `tool-reference`, `openclaw-appendix`.
- Hermes-side SKILL.md with workflow + four meta-tool definitions.
- Helper scripts: `verify_composio.sh`, `setup_api_key.sh` (both with `--no-flair` mode).
- Verification checklist with 7 post-install sections.
- Targets Hermes Agent 0.14.0. MIT licensed.
