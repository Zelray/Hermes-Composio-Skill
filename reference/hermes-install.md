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

### A.1 — Get the session-scoped MCP URL

> **Important — verified during the 2026-05-26 install:** Composio's MCP endpoint is **NOT** a static `mcp.composio.dev/mcp`. It is session-scoped, of the form `https://backend.composio.dev/tool_router/<session_id>/mcp`. You must bootstrap one session via the Composio Python SDK before attaching it to Hermes.

**Step 1 — install the Composio SDK on the Hermes host** (one-time, just to bootstrap the session ID):

```bash
# Hermes 0.14 ships with Python 3.11 — pip works directly.
pip3 install --break-system-packages composio
```

**Step 2 — create the session and capture URL + headers:**

```bash
python3 <<'PY'
import os, json
from composio import Composio
c = Composio()  # reads COMPOSIO_API_KEY from env
s = c.create(user_id=os.environ.get("COMPOSIO_USER_ID","user_default"))
print("session_id:", s.session_id)
print("mcp.url:", s.mcp.url)
print("mcp.headers:", json.dumps(dict(s.mcp.headers)))
PY
```

Expected output (your `session_id` will differ):
```
session_id: trs_xxxxxxxxxxxxx
mcp.url: https://backend.composio.dev/tool_router/trs_xxxxxxxxxxxxx/mcp
mcp.headers: {"x-api-key": "ak_..."}
```

Persist the session ID for future reuse — Composio's `composio.use(session_id)` reuses the same session URL across restarts. Save both values somewhere you can paste them later.

### A.2 — Attach the MCP server to Hermes

> **Verified during install:** `hermes mcp add --auth header` on Hermes 0.14 hard-codes `Authorization: Bearer <token>` (source: `hermes_cli/mcp_config.py:332`). Composio requires `x-api-key: <token>`. The interactive `hermes mcp add` flow therefore **cannot** attach Composio correctly. Use the direct-config-edit method below.

**Confirm the flag set anyway (for context):**

```bash
hermes mcp add --help
```

Hermes 0.14 supports: `--url`, `--command`, `--args`, `--auth {oauth,header}`, `--preset`, `--env`. Note there is no `--header NAME=VAL` flag and `--auth header` only does Bearer.

**Direct config edit — the working path:**

```bash
python3 <<'PY'
import yaml, shutil, os, datetime
cfg_path = "/root/.hermes/config.yaml"   # adjust if HERMES_HOME differs
backup = "{}.bak.composio-{}".format(cfg_path, datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ"))
shutil.copy2(cfg_path, backup)
print("backup:", backup)

with open(cfg_path) as f:
    cfg = yaml.safe_load(f)

cfg.setdefault("mcp_servers", {})
cfg["mcp_servers"]["composio"] = {
    "url": "https://backend.composio.dev/tool_router/<paste-session-id>/mcp",
    "headers": {"x-api-key": "${COMPOSIO_API_KEY}"},
    "enabled": True,
    "transport": "http",
}

with open(cfg_path, "w") as f:
    yaml.safe_dump(cfg, f, sort_keys=False, default_flow_style=False)
os.chmod(cfg_path, 0o600)
print("config written")
PY
```

Hermes stores MCP servers under the top-level `mcp_servers:` key in `~/.hermes/config.yaml` (source: `hermes_cli/mcp_config.py:6-9`). Env-var interpolation (`${COMPOSIO_API_KEY}`) works for header values.

### A.3 — Verify

```bash
hermes mcp list
# Expect: composio  http  https://backend.composio.dev/tool_router/<session-id>/mcp  enabled

hermes mcp test composio
# Expect: ✓ Connected  + ✓ Tools discovered: 6
```

The 6 tools Hermes 0.14 + Composio expose today (real names captured during 2026-05-26 install):

- `COMPOSIO_SEARCH_TOOLS` — discover tool slugs by intent
- `COMPOSIO_GET_TOOL_SCHEMAS` — fetch input schemas for selected slugs
- `COMPOSIO_MULTI_EXECUTE_TOOL` — run 1–N tool calls (single OR parallel)
- `COMPOSIO_MANAGE_CONNECTIONS` — OAuth / API-key connect flow per toolkit
- `COMPOSIO_REMOTE_BASH_TOOL` — bash in Composio's remote sandbox
- `COMPOSIO_REMOTE_WORKBENCH` — file/bulk-tool operations in the sandbox

> **Composio backend hiccups:** During the bootstrap install, Composio sometimes returns `500 / Failed to fetch API key information from DB` for a few minutes immediately after a new key is generated (DB propagation lag). If `hermes mcp test composio` fails with that exact error, wait 5 minutes and retry. Hermes-side config is fine — wait it out.

### A.4 — Install the Hermes-side overlay skill

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

### A.5 — Wire routing (optional but recommended)

**Step 1 — inspect existing providers / routes so the new routes reference real models:**

```bash
# Hermes 0.14 has no `config get` — use `config show` and grep.
hermes config show 2>&1 | grep -A3 -E "^providers:|model:"

# Or read the YAML directly:
python3 -c "import yaml; c=yaml.safe_load(open('/root/.hermes/config.yaml')); print('providers:', list((c.get('providers') or {}).keys())); print('default model:', c.get('model',{}).get('default'))"
```

Hermes installs that route everything through OpenRouter (the most common pattern as of 2026-05) will show `providers: []` and a default model slug like `anthropic/claude-sonnet-4` or `moonshotai/kimi-k2.6`. In that case use `provider: openrouter` for the route entries below and use OpenRouter model slugs (e.g. `anthropic/claude-haiku-4.5`, `anthropic/claude-sonnet-4`).

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

### A.6 — Connect a first toolkit (smoke test)

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
