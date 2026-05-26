# Install Composio on the Hermes Host

> Use this file after `api-key-setup.md` has confirmed `COMPOSIO_API_KEY` is live. Two install paths: **MCP (primary)** and **REST via skill (fallback)**. Default to MCP unless the user's environment blocks it.

## Decide which path to use

```
COMPOSIO_API_KEY present?
├── No  → return to api-key-setup.md
└── Yes
    │
    Outbound HTTPS to backend.composio.dev allowed?
    ├── Yes → MCP install (Path A)
    └── No  → REST-via-skill (Path B)

    User wants air-gapped / on-prem / dedicated Composio?
    └── Yes → REST-via-skill against custom COMPOSIO_BASE_URL (Path B)
```

Quick probe from the Hermes host:

```bash
curl -sS -o /dev/null -w "%{http_code}\n" \
  -H "x-api-key: $COMPOSIO_API_KEY" \
  https://backend.composio.dev/api/v1/toolkits
# Expect: 200. Anything else (000 / 403 / 502) → Path B.
```

---

## Path A — Composio MCP server (primary)

Hermes 0.14 supports MCP servers via `hermes mcp add`. Composio exposes a managed MCP endpoint that auto-discovers tools per connected toolkit.

### A.1 — Attach the MCP server

**Step 1 (required) — confirm the actual flag syntax for this Hermes version:**

```bash
hermes mcp add --help
```

Hermes flag names move between versions. Read the help output, then construct the add command. The required conceptual fields are: a name (`composio`), a URL (`https://mcp.composio.dev/mcp`), and an auth header carrying the API key.

**Step 2 — example shape (validate flags from --help before running):**

```bash
# Example only — replace flag names with whatever `hermes mcp add --help` shows.
# SECURITY: passing the key inline puts it in process args, shell history, and
# audit logs. Prefer Hermes' --header-from-file / --header-from-env if it
# exists. Otherwise rotate the key immediately after a successful add.
hermes mcp add composio \
  --transport http \
  --url https://mcp.composio.dev/mcp \
  --header "x-api-key:$COMPOSIO_API_KEY"
```

If `hermes mcp add` does not accept these specific flags on the installed version, do not improvise — surface the help output to the PM and ask for confirmation before substituting.

### A.2 — Verify

```bash
hermes mcp list
# Expect: composio  http  https://mcp.composio.dev/mcp  connected

hermes mcp tools composio | head -20
# Expect: a list of tool names (search_tools, execute_tool, multi_execute, manage_connections).
```

### A.3 — Install the Hermes-side overlay skill

Copy the bundled overlay from this Claude Code skill onto the Hermes host. Replace `<hermes-host>` with the actual SSH host/alias the user has configured (verify with `ssh -G <host> | head -5`; do not invent a hostname).

```bash
# From the user's local machine, run once
scp -r .claude/skills/hermes-composio/assets/hermes-composio-skill/ \
  <hermes-host>:~/.hermes/skills/composio/
```

Then on the Hermes host:

```bash
hermes skills list | grep composio
# Expect: composio  installed  <version-from-SKILL.md>
```

The overlay skill does **not** duplicate MCP tool definitions — Hermes discovers those from the MCP server. It adds:
- Sonnet-tuned tool *guidance* (when to call which tool).
- Routing hooks into `skills.config.model-router.*` so cheap Composio queries land on Haiku.
- Connect/disconnect prompts when an OAuth token is missing.

### A.4 — Wire routing (optional but recommended)

**Step 1 — list the user's configured providers so the route can reference a real one:**

```bash
hermes config get providers
# Note the provider IDs and the cheap (Haiku-class) model ID exposed by each.
```

**Step 2 — edit `~/.hermes/config.yaml` (replace `TODO_*` placeholders with values from Step 1):**

```yaml
skills:
  config:
    composio:
      # Tools that Sonnet should never route to a cheaper model
      sonnet_required:
        - GMAIL_SEND_EMAIL
        - SLACK_SEND_MESSAGE
        - GITHUB_CREATE_ISSUE
      # Read-only / list-style tools safe for Haiku
      haiku_eligible:
        - GMAIL_LIST_MESSAGES
        - GMAIL_GET_MESSAGE
        - GITHUB_LIST_ISSUES
        - SLACK_LIST_CHANNELS
        - NOTION_LIST_PAGES
      # Future v2 — allowlist scope (see CHANGELOG)
      allowed_toolkits: []   # empty = all enabled; populate later
    model-router:
      routes:
        composio_lookup:
          intent: read-only Composio query
          keywords: ["list", "get", "search", "find", "show", "fetch"]
          provider: TODO_HAIKU_PROVIDER_ID   # replace with real ID from Step 1
          model:    TODO_HAIKU_MODEL_ID      # replace with real model ID
          command_mode: oneshot
```

> **Note:** `tool_slugs_prefix` (referenced in `routing-integration.md`) is a v2 field. The current bundled Hermes-side skill matches routes by `keywords` only. Prefix-based matching ships in v1.1; until then, do not populate `tool_slugs_prefix`.

Note that `skills.config.composio.*` is **overlay data inside the native Hermes namespace** — same dual-nature pattern as `skills.config.model-router.*`.

### A.5 — Connect a first toolkit (smoke test)

```bash
# Ask Hermes (interactively) to connect Gmail
hermes chat -q "Use Composio to connect my Gmail account."
# The agent should call composio_manage_connections with action=connect, toolkit=gmail.
# Hermes prints an OAuth URL → user clicks → Composio confirms → done.

# Verify
hermes chat -q "List my Composio connections."
# Agent calls composio_manage_connections with action=status.
```

---

## Path B — REST API via Hermes skill (fallback)

Use only when Path A is blocked (firewall, air-gap, dedicated Composio deployment).

### B.1 — Install the Hermes skill in REST mode

```bash
scp -r .claude/skills/hermes-composio/assets/hermes-composio-skill/ \
  hermes-host:~/.hermes/skills/composio/

# On the Hermes host
hermes config set skills.config.composio.transport rest
hermes config set skills.config.composio.base_url https://backend.composio.dev/api/v1
# For a custom / on-prem Composio deployment:
# hermes config set skills.config.composio.base_url https://composio.internal.example.com/api/v1
```

### B.2 — How the skill talks to Composio in REST mode

The `assets/hermes-composio-skill/SKILL.md` includes the four logical tool definitions with the corresponding REST endpoints baked in:

| Tool | Method | Endpoint |
|---|---|---|
| `composio_search_tools` | POST | `/tools/search` |
| `composio_execute_tool` | POST | `/tools/execute` |
| `composio_multi_execute` | POST | `/tools/multi_execute` |
| `composio_manage_connections` | GET / POST / DELETE | `/connections` |

Auth header: `x-api-key: $COMPOSIO_API_KEY`. The skill instructs the Hermes agent to use Hermes' built-in HTTP toolset when MCP is unavailable.

### B.3 — Verify

```bash
bash ~/.hermes/skills/composio/scripts/verify_composio.sh --transport rest
# Expect: ✅ key valid, ✅ toolkits endpoint reachable, ✅ at least 1 toolkit listed.
```

---

## Rollback (both paths)

If anything goes wrong:

```bash
# MCP path
hermes mcp remove composio

# Skill path
hermes skills uninstall composio
# Or just delete the dir
rm -rf ~/.hermes/skills/composio

# Config — unset child keys explicitly. `hermes config unset` may not recurse;
# verify the result with `hermes config get skills.config.composio` afterward.
hermes config unset skills.config.composio.transport
hermes config unset skills.config.composio.base_url
hermes config unset skills.config.composio.max_multi_execute_size
hermes config unset skills.config.composio.confirm_before_write
hermes config unset skills.config.composio.daily_budget_usd
hermes config unset skills.config.composio.sonnet_required
hermes config unset skills.config.composio.haiku_eligible
hermes config unset skills.config.composio.allowed_toolkits
hermes config unset composio.api_key   # only if storing key in config.yaml

# Restart
systemctl restart hermes   # or the user's gateway restart command
```

Rollback is non-destructive. The Composio account, connected toolkits, and API key remain intact in the Composio dashboard — only the Hermes-side wiring is removed.

## One-line PM summary template

After install, hand the user this exact sentence (fill the placeholders):

> "Composio is now wired into Hermes via the **{MCP|REST}** path. Sonnet will see {N} Composio tools. Connected toolkits: {list}. To add another toolkit, ask Hermes: *'Connect my {toolkit} via Composio.'*"
