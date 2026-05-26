# Guided Composio API Key Setup

> Use this file when the user has not yet created a Composio account, or `COMPOSIO_API_KEY` is missing from the Hermes host environment. Plain-English steps; no jargon.

## What a Composio API key actually is

Composio is the middleman between Hermes and the apps the user already uses (Gmail, Slack, GitHub, Notion, etc.). The **API key** is the user's password for Hermes-to-Composio traffic. Each *connection inside* Composio (Gmail OAuth, Slack OAuth, GitHub PAT) is separate and managed in the Composio dashboard — the API key just unlocks the door.

Think of it like:
- **Composio API key** = the user's master key for the Composio building.
- **Toolkit connection** = a separate OAuth/PAT for each tenant inside (Gmail, Slack, etc.).

## Pre-flight check (run first, in order)

```bash
# 1. Hermes version (we target 0.14.0)
hermes --version

# 2. Is a key already present in the Hermes env? Check both locations:
#    (a) ~/.hermes/.env  (recommended location)
test -f ~/.hermes/.env && grep -c '^COMPOSIO_API_KEY=' ~/.hermes/.env || echo "no key in .env"
#    (b) Hermes config (only set if user explicitly chose this path). The exact
#        key path may differ between Hermes versions; if `composio.api_key` is
#        unrecognized, that is fine — it just means the key is not stored there.
hermes config get composio.api_key 2>/dev/null || true

# 3. Is the composio MCP server already attached?
hermes mcp list | grep -i composio || echo "no composio MCP yet"
```

If **either** check 2 source returns a non-empty value, **skip to `hermes-install.md`** — the user already has a key. Do not require both.

## Walkthrough: get the key

State to the user, before opening any links: *"This takes about 3 minutes. You will create a free Composio account, copy one secret string, and paste it into your Hermes config. We will then run a verification call to make sure it works."*

### Step 1 — Sign up (free tier is enough)

Open: https://platform.composio.dev/signup

The free tier covers personal accounts and is the right starting point. Composio also offers paid plans for higher rate limits and team features; do not switch the user to a paid plan unless they explicitly ask.

### Step 2 — Generate the API key

After signup, open: https://platform.composio.dev/settings

In the **API Keys** section, click **Create new key**, name it `hermes-$(hostname)` (so the user can recognize which host it belongs to later), and copy the value. The exact prefix is set by Composio and may change — do not hard-code prefix assumptions; just trust the value the dashboard returns.

> **Security note:** This key authenticates *all* of Hermes' Composio calls. Treat it like a password. Never paste it into chat, screenshots, commit messages, or public repos. If the user runs any backup or sync of `~/.hermes/`, verify that `COMPOSIO_API_KEY` is on the denylist before the next run.

### Step 3 — Store the key on the Hermes host

**Recommended location** (Hermes auto-loads it, no shell config needed). Create the file with mode `600` *before* writing so the secret is never world-readable:

```bash
# On the Hermes host
umask 077
touch ~/.hermes/.env
chmod 600 ~/.hermes/.env

# If the file already contains a COMPOSIO_API_KEY line, strip it first to avoid duplicates:
grep -v '^COMPOSIO_API_KEY=' ~/.hermes/.env > ~/.hermes/.env.tmp && mv ~/.hermes/.env.tmp ~/.hermes/.env

echo "COMPOSIO_API_KEY=<paste-key-here>" >> ~/.hermes/.env
chmod 600 ~/.hermes/.env   # belt + suspenders
```

The bundled `setup_api_key.sh` does all of this for you — prefer running that script over hand-editing.

**Alternative — Hermes config** (use only if the user explicitly prefers config.yaml over .env):

```bash
hermes config set composio.api_key "<paste-key-here>"
```

This writes to `~/.hermes/config.yaml`. Hermes redacts it in `hermes config` output, but the file itself is plaintext — `chmod 600` it.

**Do NOT** export `COMPOSIO_API_KEY` in `~/.bashrc` / `~/.zshrc` unless the user explicitly wants it visible to every shell session. The `.env` approach is scoped to Hermes only.

### Step 4 — Verify the key works

```bash
# Bundled verification script (after Hermes-side skill is installed)
bash ~/.hermes/skills/composio/scripts/verify_composio.sh

# Or a direct curl probe (no skill needed)
curl -sS -H "x-api-key: $COMPOSIO_API_KEY" \
  https://backend.composio.dev/api/v1/toolkits | head -c 200
```

Expected: a JSON response listing toolkits. If the response is `{"error":"unauthorized"}`, the key was copied wrong — regenerate at https://platform.composio.dev/settings.

### Step 5 — One-line PM summary

After verification, give the user a single sentence: *"Composio API key is live in `~/.hermes/.env`. Hermes can now reach Composio. Next step: install the Composio MCP server so Sonnet can actually call the tools."*

Then route to `hermes-install.md`.

## Common failures

| Symptom | Likely cause | Fix |
|---|---|---|
| `{"error":"unauthorized"}` on curl probe | Key copy-paste added a leading/trailing space, or the key was rotated in the dashboard. | Regenerate at platform.composio.dev/settings, rewrite `.env`, retry. |
| `hermes config get composio.api_key` returns empty after edit | Hermes was not restarted; `.env` is loaded on Hermes startup. | `systemctl restart hermes` (or the user's gateway restart command). |
| Key works locally but fails on Hermes server | Outbound HTTPS to `backend.composio.dev` blocked by firewall. | Whitelist `*.composio.dev:443` or fall back to REST-via-skill mode (see `hermes-install.md` § REST fallback). |
| User can't reach platform.composio.dev | Geoblock or corporate proxy. | Composio supports EU region — set `COMPOSIO_BASE_URL=https://backend.eu.composio.dev` in `.env`. |

## Rotation policy

Recommend rotating the Composio API key every 90 days, and immediately if:
- The Hermes host shows unfamiliar Composio activity in https://platform.composio.dev/logs.
- The key was accidentally committed to git or pasted in chat.
- A team member with key access leaves the project.

Rotation is a 2-command process: generate a new key in the dashboard, then `echo "COMPOSIO_API_KEY=<new>" > ~/.hermes/.env && systemctl restart hermes`. The old key revokes on demand from the dashboard.
