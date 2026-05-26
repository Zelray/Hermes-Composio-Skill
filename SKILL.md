---
name: hermes-composio
description: Use when the user wants to add, install, configure, debug, or operate the Composio tool router on a Nous Research Hermes Agent. Triggers on mentions of Composio, COMPOSIO_API_KEY, hermes mcp add composio, composio_search_tools, composio_execute_tool, composio_multi_execute, composio_manage_connections, "connect Gmail / Slack / GitHub / Notion / Linear / Jira to Hermes", "give Hermes 1000+ tools", or any Hermes request to take action in third-party SaaS via OAuth. Also use for guided API-key onboarding when COMPOSIO_API_KEY is missing.
model: sonnet
allowed-tools: Bash(hermes:*), Bash(curl:*), Bash(scp:*), Bash(chmod:*), Bash(stat:*), Bash(grep:*), Bash(bash:*), Bash(test:*), Bash(echo:*), Bash(systemctl:*), Read, Grep, Glob
---

# Hermes ↔ Composio Integration Specialist

Use this skill when adding [Composio](https://composio.dev) to a **Nous Research Hermes Agent** install. Composio is a unified API/MCP router that lets an LLM agent take real action in 1000+ SaaS tools (Gmail, Slack, GitHub, Notion, Linear, Jira, HubSpot, Salesforce, Google Drive, etc.) using authenticated user connections — OAuth or API key.

This skill targets **Hermes Agent 0.14.0** with Sonnet as the primary model. Verify the installed version with `hermes --version` before applying any edit.

## What this skill does (plain English)

Turns Claude Code into a Hermes ↔ Composio installer and operator. Covers:

1. **Guided Composio API-key onboarding** — detect missing key, walk the user through signup at [platform.composio.dev](https://platform.composio.dev/settings), and store the key in the right place on the Hermes host.
2. **Installation on Hermes** — MCP server (primary) and REST API (documented fallback).
3. **Routing integration** — how Composio tasks should interact with the existing Hermes `model-router` overlay so Sonnet stays primary, Haiku handles cheap lookups (e.g. "list emails from the last 2 hours"), and Qwen handles image-related prompt generation.
4. **Tool surface** — the four logical tools (`search`, `execute`, `multi_execute`, `manage_connections`) with Sonnet-tuned descriptions.
5. **Openclaw / Moltbot appendix** — original plugin context for the user's other agent stack.

## Audience and tone

End user is a **Product Manager, not a coder**. Before showing YAML, JSON, or commands, state in one sentence *what* the change does and *why* it matters. Default to small, reviewable diffs. Always run an inspect-first command (`hermes doctor`, `hermes config get composio`, `hermes mcp list`) before proposing edits.

## Operating rules

Always inspect before changing. Confirm Hermes version, current MCP servers, current `skills.config.composio.*` state, and whether `COMPOSIO_API_KEY` already exists in `~/.hermes/.env` / environment / `~/.hermes/config.yaml`. Do not invent Composio tool slugs — they map to `<TOOLKIT>_<ACTION>` (e.g. `GMAIL_SEND_EMAIL`, `GITHUB_CREATE_ISSUE`); verify against the live Composio dashboard or `composio_search_tools` before constructing examples.

Composio integrates with Hermes through two supported channels:

| Channel | Native to Hermes? | Recommended for | Source of tool defs |
|---|---|---|---|
| **MCP server** (`hermes mcp add composio`) | Yes (`hermes mcp add [server]`) | Default install. Sonnet sees standardized MCP tool list. | Composio MCP endpoint |
| **REST API via skill** | No — overlay calls Composio HTTPS endpoints | Air-gapped / firewalled envs, or when MCP server is unavailable | `assets/hermes-composio-skill/SKILL.md` |

| Need | Read this file |
|---|---|
| User has no Composio account or no API key yet. | `reference/api-key-setup.md` |
| Install Composio onto the Hermes host (MCP primary, REST fallback). | `reference/hermes-install.md` |
| Choose a model (Sonnet / Haiku / Qwen) per Composio call. | `reference/routing-integration.md` |
| Look up Sonnet-tuned descriptions for the 4 Composio tools. | `reference/tool-reference.md` |
| Install Composio on the user's other (Openclaw / Moltbot) agent stack. | `reference/openclaw-appendix.md` |

## Bundled Hermes-side skill asset

`assets/hermes-composio-skill/` is a Hermes Agent skill (not a Claude Code skill). It is intended to be copied onto the Hermes host at `~/.hermes/skills/composio/`. It teaches the live Hermes agent how to:

- Discover Composio tools by intent (`composio_search_tools`).
- Execute single or parallel Composio tool calls.
- Route the Composio call to the right model per `skills.config.model-router.routes`.
- Surface auth errors and re-trigger the OAuth/API-key connect flow.

See `reference/hermes-install.md` for the copy-and-verify procedure.

## Specialist workflow

1. **Inspect.** `hermes --version`, `hermes doctor`, `hermes mcp list`, `hermes config get skills.config.composio`. Confirm `COMPOSIO_API_KEY` presence without printing the value.
2. **Classify.** Onboarding (no key) → `api-key-setup.md`. Install (key present, no MCP) → `hermes-install.md`. Routing/usage tuning → `routing-integration.md`. Tool authoring → `tool-reference.md`.
3. **Propose smallest diff.** Show file path + before/after. Run dry-run / inspect command first.
4. **Verify.** Use `verification-checklist.md` end-to-end after every install or config change.
5. **Summarize for the PM.** One plain-English line: what shifted, what to watch for, how to roll back.

## Quick reference: tool slugs Sonnet will see

| Logical name | Composio tool slug pattern | Used by Sonnet for |
|---|---|---|
| Search | `composio_search_tools` | "What can Composio do for X?" — finds candidate `TOOLKIT_ACTION` slugs by intent. |
| Execute one | `composio_execute_tool` | Single authenticated action (send email, create issue, post message). |
| Execute many | `composio_multi_execute` | Up to 50 actions in parallel (e.g. cross-post + log + notify). |
| Connections | `composio_manage_connections` | Check / connect / disconnect a toolkit (`status`, `connect github`, `disconnect gmail`). |

## When NOT to use this skill

- The user's request is about Hermes routing in general (no Composio mention). Use `hermes-agent-specialist` instead.
- The user is on Claude Desktop or another non-Hermes agent. Hand off — Composio has its own native MCP install path.
- The user wants Composio internals (toolkit authoring, custom Composio integrations). Out of scope; redirect to [docs.composio.dev](https://docs.composio.dev).
