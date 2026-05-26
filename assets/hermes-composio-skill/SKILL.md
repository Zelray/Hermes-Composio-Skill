---
name: composio
description: Use when the user asks Hermes to take action in third-party SaaS (Gmail, Slack, GitHub, Notion, Linear, Jira, Salesforce, HubSpot, Google Drive, Asana, Trello, 1000+ more) via Composio. Triggers on "send an email", "create a ticket", "post to Slack", "list my issues", "connect my {toolkit}", and any explicit mention of Composio. Routes calls to Sonnet, Haiku, or local Qwen per skills.config.model-router.routes. Supports MCP transport (default) and REST API transport (fallback).
---

<!--
  IMPORTANT: This SKILL.md is a HERMES AGENT skill, NOT a Claude Code skill.
  Do NOT copy this directory into ~/.claude/skills/ or any Claude skill path.
  Install path on the Hermes host: ~/.hermes/skills/composio/

  The surrounding Claude Code skill (.claude/skills/hermes-composio/) is the
  Claude-side wrapper that teaches Claude how to install and configure this
  skill onto a running Hermes Agent. This nested directory is one of its
  bundled assets that ships into Hermes.
-->

# Composio Tool Router for Hermes

This Hermes skill connects Hermes to [Composio](https://composio.dev) — a unified router that authenticates Hermes against 1000+ third-party SaaS tools (Gmail, Slack, GitHub, Notion, Linear, Jira, HubSpot, Salesforce, etc.).

## Transport

This skill supports two transports. Inspect `skills.config.composio.transport`:

| Value | Means | Tool discovery |
|---|---|---|
| `mcp` (default) | Hermes calls the Composio MCP server registered via `hermes mcp add composio`. | Auto from MCP |
| `rest` | Hermes calls Composio REST via the built-in HTTP toolset. | From this skill's definitions |

If unset, default to `mcp` and check `hermes mcp list` for a `composio` entry.

## Required config

Read from `~/.hermes/config.yaml`:

```yaml
skills:
  config:
    composio:
      transport: mcp           # or rest
      base_url: https://backend.composio.dev/api/v1   # REST only
      max_multi_execute_size: 10
      confirm_before_write: true
      daily_budget_usd: 5.00
      sonnet_required: []      # tool slugs that must stay on Sonnet
      haiku_eligible: []       # read-only slugs eligible for Haiku
      allowed_toolkits: []     # empty = all; non-empty = whitelist (v2)
```

API key is read from `COMPOSIO_API_KEY` env var (preferred) or `composio.api_key` in `config.yaml` (fallback). Never print the key in agent responses.

## The six meta-tools

Composio Tool Router exposes six meta-tools. Composio slugs (`GMAIL_SEND_EMAIL`, etc.) are *arguments* to `COMPOSIO_MULTI_EXECUTE_TOOL`, not separate tools.

### 1. `COMPOSIO_SEARCH_TOOLS`

Search the Composio catalog for slug(s) matching the user's intent. Call this BEFORE `COMPOSIO_MULTI_EXECUTE_TOOL` when the slug is not yet known. Returns candidate slugs + descriptions.

Args: `query` (string, required), `toolkits` (array of toolkit slugs, optional), `limit` (int, default 5).

### 2. `COMPOSIO_GET_TOOL_SCHEMAS`

Fetch the input JSON-schema for one or more known slugs. Call this after SEARCH_TOOLS when you need the exact argument shape before executing.

Args: `tool_slugs` (array of uppercase slugs, required).

### 3. `COMPOSIO_MULTI_EXECUTE_TOOL`

Execute 1–N Composio tool calls. This is the single execution surface — both single and bulk calls use this tool. For a single call, pass `executions` of length 1. Up to `skills.config.composio.max_multi_execute_size` (default 10) calls in parallel.

Args: `executions` (array of `{tool_slug, arguments}` objects).

### 4. `COMPOSIO_MANAGE_CONNECTIONS`

Check, connect, or disconnect a toolkit.

Args: `action` (one of `status`, `connect`, `disconnect`, `list`), `toolkits` (array, omitted when action=list).

### 5. `COMPOSIO_REMOTE_BASH_TOOL` (advanced)

Run a bash command inside Composio's remote sandbox. Use only for file ops on Composio-managed remote files. Not a general system-administration tool.

Args: `command` (string, required).

### 6. `COMPOSIO_REMOTE_WORKBENCH` (advanced)

Process remote files or script bulk tool execution in Composio's sandbox. Higher-level than REMOTE_BASH_TOOL — for multi-step file pipelines that should run on Composio's infra.

Args: `workflow` (object, schema via GET_TOOL_SCHEMAS).

## Workflow the agent follows

1. **Detect Composio intent.** User wants an action in Gmail / Slack / GitHub / Notion / Linear / Jira / etc., or explicitly mentions Composio.
2. **Route by complexity.** Read `skills.config.model-router.routes.composio_lookup`, `composio_action`, `composio_image_prompt`. Match the user's request against `keywords` and the candidate tool slug's prefix (`LIST_`, `GET_`, `SEARCH_` → lookup; `CREATE_`, `SEND_`, `UPDATE_`, `REPLY_` → action; `DELETE_` → always confirm + action).
3. **Discover slug.** Call `COMPOSIO_SEARCH_TOOLS` with `query` = user's intent and `toolkits` = filter from explicit context. Pick the top match whose name matches the user's verb.
4. **Fetch schema** (if not in scrollback). Call `COMPOSIO_GET_TOOL_SCHEMAS` with the chosen slug(s) so the argument shape is exact before execution.
5. **Verify connection.** If the toolkit has not been used this session, call `COMPOSIO_MANAGE_CONNECTIONS action=status toolkits=[<toolkit>]`. If not connected, call `COMPOSIO_MANAGE_CONNECTIONS action=connect toolkits=[<toolkit>]`, surface the auth URL to the user, and pause until the user confirms.
6. **Confirm destructive / outbound ops.** If `confirm_before_write` is true AND the slug starts with `DELETE_`, `ARCHIVE_`, `REVOKE_`, `SEND_`, or `REPLY_`: state the planned action in plain English and wait for explicit "yes". `CREATE_` and `UPDATE_` do NOT require confirmation by default — they generate too many prompts and the user disables the safety net. The PM can opt into stricter confirmation with `skills.config.composio.confirm_create_update: true`.
7. **Execute.** Call `COMPOSIO_MULTI_EXECUTE_TOOL` with `executions` of length 1 (single call) or N (bulk fan-out).
8. **Summarize.** Translate the JSON result into one or two sentences for the user.

## Helper scripts

| Script | Purpose |
|---|---|
| `scripts/verify_composio.sh` | One-shot health check: key valid, transport reachable, ≥1 toolkit listed. |
| `scripts/setup_api_key.sh` | Guided key onboarding (signup link, paste, write to `.env`, verify). |

Both scripts are safe to run repeatedly. They never overwrite an existing `COMPOSIO_API_KEY` without explicit `--rotate` confirmation.

## Routing tie-in

This skill reads `skills.config.model-router.routes.composio_*` set by the Claude Code wrapper `hermes-composio`. **If the `model-router` overlay is not installed or `skills.config.model-router.routes` is empty, this section is a no-op** — all Composio calls run on the current session model with no per-intent routing. Report that state to the user once on first use rather than failing silently.

When a route matches:

- `command_mode: oneshot` → suggest `hermes -z "<request>" --provider <route.provider> --model <route.model>`.
- `command_mode: current_session` → stay on current session model; execute Composio call directly.
- `command_mode: advise` → tell the user the exact `/model provider:model` switch, then execute.
- `delegate_model` set → use Hermes `delegation.*` for that subtask only.

Never persist `/model` changes via `--global` unless the user explicitly asks.

## Auth error recovery

If `COMPOSIO_MULTI_EXECUTE_TOOL` returns `unauthorized` or `connection_not_found`:

1. State plainly: "I need to reconnect your {toolkit} via Composio."
2. Call `COMPOSIO_MANAGE_CONNECTIONS action=connect toolkits=[<toolkit>]`.
3. Print the auth URL.
4. Wait for the user to confirm. Do not retry the original call until the user says they have completed the connect flow.

**Special case — DB propagation lag.** If the error message is `Failed to fetch API key information from DB` (code 10401 / 809), the key is being propagated by Composio's backend (~5 min after key generation). Tell the user: "Composio is still propagating your new key. I'll retry in 5 minutes." Do NOT trigger a reconnect flow — the key is fine, the backend just isn't ready.

## What this skill does NOT do

- It does not authenticate users TO Hermes (that's the gateway).
- It does not store OAuth tokens (Composio handles that).
- It does not bypass Hermes' native routing — it sits on top of `model-router`.
- It does not modify Composio's own configuration (toolkit enablement happens at platform.composio.dev).

## References

- Composio docs: https://docs.composio.dev
- Composio Tool Router overview: https://docs.composio.dev/tool-router/overview
- Composio platform: https://platform.composio.dev
- Hermes Agent CLI reference: https://hermes-agent.nousresearch.com/docs/reference/cli-commands
