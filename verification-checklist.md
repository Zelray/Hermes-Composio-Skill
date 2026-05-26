# Verification Checklist

> Run after **every** install or config change. Quoted commands are exact — match them. The Hermes agent's PM-facing summary should reflect each ✅ before the user signs off.

## 0. Pre-flight (read-only — safe anytime)

- [ ] `hermes --version` returns **0.14.0** (or the user's stated target version).
- [ ] `hermes doctor` shows zero red items.
- [ ] `hermes config check` reports no schema errors.
- [ ] `~/.hermes/.env` exists and is mode `600`: `stat -c '%a' ~/.hermes/.env` → `600`.

> **Note:** Hermes 0.14 has no `hermes config get` subcommand. Use `hermes config show` and grep, or read `~/.hermes/config.yaml` directly with Python/yq.

## 1. API key

- [ ] `COMPOSIO_API_KEY` is set (env, `.env`, or `hermes config get composio.api_key`).
- [ ] Key length ≥ 20 characters.
- [ ] Key has no whitespace.
- [ ] `bash ~/.hermes/skills/composio/scripts/verify_composio.sh` returns exit 0.
- [ ] Direct probe — **source `.env` into the current shell first if the key is stored there**. Use v3 endpoint (v1 is deprecated, returns 410):
  ```bash
  set -a; source ~/.hermes/.env; set +a
  curl -sS -o /dev/null -w "%{http_code}" -H "x-api-key:$COMPOSIO_API_KEY" https://backend.composio.dev/api/v3/toolkits
  ```
  Expect `200`. If you see `401 / Failed to fetch API key information from DB`, the key is propagating — wait 5 minutes and retry.

## 2a. Transport (Path A — MCP)

- [ ] `hermes mcp list | grep composio` shows an `enabled` entry (the URL will look like `https://backend.composio.dev/tool_router/trs_xxxxxxxx/mcp` — session-scoped, not the static `mcp.composio.dev/mcp`).
- [ ] `hermes mcp test composio` returns `✓ Connected` + `✓ Tools discovered: 6` — the six real meta-tools: `COMPOSIO_SEARCH_TOOLS`, `COMPOSIO_GET_TOOL_SCHEMAS`, `COMPOSIO_MULTI_EXECUTE_TOOL`, `COMPOSIO_MANAGE_CONNECTIONS`, `COMPOSIO_REMOTE_BASH_TOOL`, `COMPOSIO_REMOTE_WORKBENCH`.

## 2b. Transport (Path B — REST fallback)

- [ ] `hermes config get skills.config.composio.transport` returns `rest`.
- [ ] `hermes config get skills.config.composio.base_url` resolves to a reachable URL.
- [ ] `bash ~/.hermes/skills/composio/scripts/verify_composio.sh --transport rest` returns exit 0.

## 3. Hermes-side skill

- [ ] `~/.hermes/skills/composio/SKILL.md` exists.
- [ ] `~/.hermes/skills/composio/scripts/verify_composio.sh` exists and is executable (`chmod 755`).
- [ ] `~/.hermes/skills/composio/scripts/setup_api_key.sh` exists and is executable.
- [ ] `hermes skills list | grep composio` shows the skill as installed.

## 4. Routing wiring

`hermes config get` doesn't exist in 0.14 — read the YAML directly:

```bash
python3 -c "
import yaml
c = yaml.safe_load(open('/root/.hermes/config.yaml'))
r = c['skills']['config']['model-router']['routes']
for k in ['composio_lookup','composio_action','composio_image_prompt']:
    print(f\"{k}: {r.get(k,{}).get('model','MISSING')}\")"
```

- [ ] `composio_lookup` populated with a Haiku-class model slug.
- [ ] `composio_action` populated with a Sonnet-class model slug.
- [ ] `composio_image_prompt` populated (if image-prompt routing is enabled).
- [ ] Each route's `provider` matches an entry in `providers:` (or is `openrouter` if the install is OpenRouter-only).

## 5. Smoke test (live)

Run these three Hermes interactions and verify behavior:

- [ ] **Read (Haiku route).**
  - Prompt: *"List my last 5 Composio toolkits."*
  - Expect: `composio_manage_connections action=list` is called, Haiku-route summary is returned.
  - Verify model used: `hermes logs tail -n 50 | grep -i 'model='`.

- [ ] **Write (Sonnet route).**
  - Prompt: *"Draft (don't send) an email to me at <user-email> subject 'Composio test'."*
  - Expect: agent drafts the email, asks for confirmation, then on "yes" calls `composio_execute_tool tool_slug=GMAIL_SEND_EMAIL`. Model used = Sonnet.

- [ ] **Auth error recovery.**
  - Force a disconnected toolkit: `composio_manage_connections action=disconnect toolkits=[github]` (via agent).
  - Prompt: *"Create a GitHub issue titled 'verify-test' in <some-test-repo>."*
  - Expect: agent detects missing connection, calls `action=connect`, surfaces auth URL, pauses.

## 6. PM-facing summary

After all the above, the agent must say to the user (template):

> "Composio is verified end-to-end on Hermes.
> Path: **{MCP | REST}**.
> Connected toolkits: **{list}**.
> Routing: reads → Haiku, writes → Sonnet, image prompts → Qwen 4B.
> To add another toolkit, ask: *'Connect my {toolkit} via Composio.'*
> To roll back, run: `hermes mcp remove composio` (Path A) or `hermes skills uninstall composio` (Path B)."

## 7. Backup hygiene (only if you back up `~/.hermes/`)

- [ ] Confirm `~/.hermes/.env` is **excluded** from any backup or sync of `~/.hermes/`.
- [ ] Confirm `COMPOSIO_API_KEY` is on the backup's credential-scan denylist.
- [ ] If a dry-run mode exists, run it and grep for `composio` — it should return nothing.

## Common failures

| Symptom | Probably means | Fix |
|---|---|---|
| `hermes mcp list` does not show composio | MCP add command failed silently | Re-run `hermes mcp add composio ...` with full URL+header. |
| `verify_composio.sh` reports HTTP 401 | Wrong key, or key got rotated in dashboard | Re-run `setup_api_key.sh --rotate`. |
| `verify_composio.sh` reports HTTP 000 | Network reachability — firewall, DNS, or proxy | Check egress to `*.composio.dev:443`. If blocked, switch to REST path with custom base URL. |
| Smoke test hangs on connect URL | User didn't complete OAuth in browser | Re-issue `composio_manage_connections action=connect` and confirm Composio dashboard shows the toolkit as connected. |
| Routing always uses Sonnet for reads | `tool_slugs_prefix` not configured | Edit `skills.config.model-router.routes.composio_lookup.tool_slugs_prefix` to include `GMAIL_LIST`, `GITHUB_LIST`, etc. |

If any checklist item fails: stop, do not advance, fix root cause, re-run from item 0.
