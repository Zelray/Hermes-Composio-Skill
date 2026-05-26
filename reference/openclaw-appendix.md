# Openclaw / Moltbot / Clawdbot Appendix

> Use this file only when the user explicitly wants to install Composio on their **non-Hermes** agent stack (Moltbot / Clawdbot, the project the user has previously called "Openclaw"). Hermes install lives in `hermes-install.md` — do not mix them.

## What this stack actually is

The folder previously at `openclaw-composio/` in this project root was the **moltbot/clawdbot** repository — an open-source multi-channel agent runtime (Discord, Slack, Telegram, iMessage, WhatsApp Web, etc.) that the user runs in parallel with Hermes. The Composio integration ships inside that repo as a TypeScript plugin at `extensions/composio/`.

That repo is **not** a Claude Code skill, **not** a Hermes skill, and **not** an MCP server. It is a runtime plugin loaded by the moltbot CLI at startup.

## When to recommend this path

| Scenario | Path |
|---|---|
| User wants Composio in **Hermes** (primary case) | `hermes-install.md` |
| User wants Composio in **moltbot/clawdbot** as well | This file |
| User wants Composio only in moltbot, not Hermes | This file — but flag the inconsistency for the user. The user's stated primary agent is Hermes. |

## Install moltbot-side

### 1 — Confirm the runtime is running

```bash
moltbot --version
moltbot channels status --probe
```

If `moltbot` is not installed, the user should install it from https://molt.bot first. This skill does not cover moltbot bootstrapping.

### 2 — Install the Composio plugin

The plugin lives at `extensions/composio/` inside the moltbot repo. Install path depends on whether the user is on the published moltbot or a local dev checkout.

**Published moltbot (most users):**

```bash
moltbot plugin install @moltbot/composio
```

**Local checkout (if the user is hacking on moltbot itself):**

```bash
cd <moltbot-repo>
pnpm install
pnpm build
# Plugin is loaded automatically from extensions/composio at moltbot startup.
```

### 3 — Configure

```bash
# Option A — env var
export COMPOSIO_API_KEY=<key>

# Option B — moltbot config
moltbot config set plugins.composio.enabled true
moltbot config set plugins.composio.apiKey "<key>"
moltbot config set plugins.composio.defaultUserId "<user-id-from-composio-dashboard>"
```

The same Composio API key works for both Hermes and moltbot — the key is account-scoped, not host-scoped. The user does NOT need a second Composio account.

### 4 — CLI verification

```bash
moltbot composio list                       # list available toolkits
moltbot composio status                     # which toolkits are connected
moltbot composio connect github             # connect a toolkit
moltbot composio search "send email"        # search tools by intent
```

These are the verified commands from the original `openclaw-composio/extensions/composio/README.md`. They differ from Hermes (which uses `hermes mcp` and `hermes skills`).

## Tool surface on moltbot vs Hermes

The four logical tools are the same. The wire-up is different.

| Tool | Hermes (MCP path) | moltbot (plugin path) |
|---|---|---|
| `composio_search_tools` | MCP tool, auto-discovered | Plugin-registered agent tool |
| `composio_execute_tool` | MCP tool | Plugin-registered agent tool |
| `composio_multi_execute` | MCP tool | Plugin-registered agent tool, capped at 50 |
| `composio_manage_connections` | MCP tool | Plugin-registered agent tool |

Behaviorally identical from the user's perspective. Implementation-wise: moltbot calls Composio REST directly via the plugin's TypeScript code; Hermes (Path A) calls Composio via MCP.

## Cross-stack consistency

If the user runs **both** Hermes and moltbot, keep these aligned to avoid surprises:

1. **Same API key, but tracked once.** Store in `~/.hermes/.env` and also in the moltbot config — but treat the Hermes copy as canonical. Rotation: rotate in Composio dashboard, then update both `.env` files, then restart both services.
2. **Same allowed toolkits.** If/when the v2 allowlist lands (`skills.config.composio.allowed_toolkits` on Hermes, `plugins.composio.allowedToolkits` on moltbot), populate both with the same list.
3. **Same routing philosophy.** moltbot does not currently have a `model-router` overlay equivalent — it uses a flat model setting per channel. So routing tuning (Sonnet/Haiku/Qwen split) is Hermes-only. Tell the user explicitly: *"Routing optimization only applies on the Hermes side. moltbot will use whatever default model you've set per channel."*

## What to do with the existing `openclaw-composio/` folder

If you are also running the upstream moltbot/clawdbot stack, the suggested lifecycle is:

1. Install Composio inside moltbot per the steps above.
2. Keep the moltbot/clawdbot source available — either upstream (`git clone https://github.com/moltbot/moltbot`) or as a local checkout you maintain.

> **On deleting a local moltbot/clawdbot checkout:** if the user wants to remove the local copy after migrating to this Hermes-Composio skill, treat the deletion as a destructive op. Run `git status` inside the checkout first to confirm no uncommitted work, push any local commits to the user's fork, and then ask the user for an explicit "delete now" before issuing `rm -rf`. Never delete without that explicit confirmation in the current session.

## Source attribution

This appendix and the four-tool surface described in `tool-reference.md` are adapted from `openclaw-composio/extensions/composio/README.md` (moltbot/clawdbot Composio plugin, MIT licensed). Tool names, argument shapes, and CLI command patterns originated there; the Sonnet-tuned descriptions, routing integration, and Hermes-specific install paths are original to this skill.
