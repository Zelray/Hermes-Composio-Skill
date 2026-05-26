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

## The four meta-tools

The agent picks from these four. Composio slugs (`GMAIL_SEND_EMAIL`, etc.) are *arguments* to `composio_execute_tool`, not separate tools.

### 1. `composio_search_tools`

Search Composio's catalog for a slug matching the user's intent. Call BEFORE `composio_execute_tool` when the slug is not yet known. Returns up to `limit` candidates with `slug`, `toolkit`, `description`, and `parameters` schema.

Args: `query` (string, required), `toolkits` (array of toolkit slugs, optional), `limit` (int, default 5).

### 2. `composio_execute_tool`

Execute one Composio tool. Requires a confirmed `tool_slug` and `arguments` matching its schema.

Args: `tool_slug` (uppercase, required), `arguments` (object, required).

### 3. `composio_multi_execute`

Run up to `skills.config.composio.max_multi_execute_size` (default 10) calls in parallel. Use only when calls are independent.

Args: `executions` (array of `{tool_slug, arguments}` objects).

### 4. `composio_manage_connections`

Check, connect, or disconnect a toolkit.

Args: `action` (one of `status`, `connect`, `disconnect`, `list`), `toolkits` (array, omitted when action=list).

## Workflow the agent follows

1. **Detect Composio intent.** User wants an action in Gmail / Slack / GitHub / Notion / Linear / Jira / etc., or explicitly mentions Composio.
2. **Route by complexity.** Read `skills.config.model-router.routes.composio_lookup`, `composio_action`, `composio_image_prompt`. Match the user's request against `keywords` and the candidate tool slug's prefix (`LIST_`, `GET_`, `SEARCH_` → lookup; `CREATE_`, `SEND_`, `UPDATE_`, `REPLY_` → action; `DELETE_` → always confirm + action).
3. **Discover slug.** Call `composio_search_tools` with `query` = user's intent and `toolkits` = filter from explicit context. Pick the top match whose name matches the user's verb.
4. **Verify connection.** If the toolkit has not been used this session, call `composio_manage_connections action=status toolkits=[<toolkit>]`. If not connected, call `composio_manage_connections action=connect toolkits=[<toolkit>]`, surface the auth URL to the user, and pause until the user confirms.
5. **Confirm destructive / outbound ops.** If `confirm_before_write` is true AND the slug starts with `DELETE_`, `ARCHIVE_`, `REVOKE_`, `SEND_`, or `REPLY_`: state the planned action in plain English and wait for explicit "yes". `CREATE_` and `UPDATE_` do NOT require confirmation by default — they generate too many prompts and the user disables the safety net. The PM can opt into stricter confirmation with `skills.config.composio.confirm_create_update: true`.
6. **Execute.** Call `composio_execute_tool` (single) or `composio_multi_execute` (parallel).
7. **Summarize.** Translate the JSON result into one or two sentences for the user.

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

If `composio_execute_tool` returns `unauthorized` or `connection_not_found`:

1. State plainly: "I need to reconnect your {toolkit} via Composio."
2. Call `composio_manage_connections action=connect toolkits=[<toolkit>]`.
3. Print the auth URL.
4. Wait for the user to confirm. Do not retry the original call until the user says they have completed the connect flow.

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
