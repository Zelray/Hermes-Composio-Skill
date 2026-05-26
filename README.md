# 🏄 Hermes-Composio-Skill

> Hook your [Nous Research Hermes Agent](https://hermes-agent.nousresearch.com) into [Composio](https://composio.dev) and let it actually *do stuff* — send emails, file tickets, post to Slack, all 1000+ SaaS tools — instead of just talking about them. Built for Sonnet-on-Hermes, plays nice with model routing, walks Product-Manager-types through setup without making them cry.

**Stoke level:** 🌊🌊🌊🌊
**Target:** Hermes Agent **0.14.0**
**License:** MIT
**Repo:** https://github.com/Zelray/Hermes-Composio-Skill

---

## 🤙 Install — Option 1: Tell Your Agent To Do It (Recommended)

You're already running [Claude Code](https://claude.com/claude-code), right? Cool. Open it, then drop this in chat:

> Hey, install this Hermes skill for me: **https://github.com/Zelray/Hermes-Composio-Skill**

Claude reads the repo, clones the skill into `~/.claude/skills/hermes-composio/`, and from that moment on, **it knows the install playbook**. Next thing you say:

> Now install Composio on my Hermes.

Claude takes the wheel:

- Asks how to SSH into your Hermes box (don't make it guess — that way lies wipeouts).
- Inspects your Hermes (`hermes --version`, `hermes doctor`, `hermes mcp list`, `.env` check).
- If you have no Composio account → walks you through signup at [platform.composio.dev](https://platform.composio.dev) and pastes the key into `~/.hermes/.env` for you (chmod 600, no leaks broseph).
- Adds the Composio MCP server to Hermes with the right flags for *your* Hermes version.
- Drops the bundled Hermes-side skill into `~/.hermes/skills/composio/`.
- Wires Sonnet/Haiku/Qwen routing so cheap reads land on Haiku and Sonnet handles the smart stuff.
- Runs the end-to-end verify script.
- Gives you a one-line "here's what just happened" summary.

**Total time:** about 5 minutes if you have a Composio key, 8 if you don't.

---

## 🛠️ Install — Option 2: Manual (For People Who Like Friction)

You do you. Steps:

```bash
# 1. Clone the skill into your Claude Code skills directory (user-scope; or use the project-scope path if you prefer)
git clone https://github.com/Zelray/Hermes-Composio-Skill ~/.claude/skills/hermes-composio

# 2. Open Claude Code in a fresh session so the skill registry picks it up.

# 3. Verify the skill loaded
#    In Claude Code: type `/` and look for `hermes-composio` in the slash menu,
#    or just ask Claude "list my skills" — it'll show up under user skills.

# 4. SSH into your Hermes host yourself
ssh youruser@your-hermes-host

# 5. Get a Composio API key from https://platform.composio.dev/settings
#    Then back on your Hermes host:
umask 077
touch ~/.hermes/.env && chmod 600 ~/.hermes/.env
echo "COMPOSIO_API_KEY=ck_paste_your_key_here" >> ~/.hermes/.env

# 6. Attach Composio's MCP server (check `hermes mcp add --help` for your version's exact flags first)
hermes mcp add composio --url https://mcp.composio.dev/mcp --auth header

# 7. From your local machine, copy the Hermes-side skill onto the server
scp -r ~/.claude/skills/hermes-composio/assets/hermes-composio-skill/ \
  your-hermes-host:~/.hermes/skills/composio/

# 8. Edit ~/.hermes/config.yaml on the Hermes host to add `skills.config.composio.*` and
#    `skills.config.model-router.routes.composio_*` per reference/routing-integration.md

# 9. Verify
bash ~/.hermes/skills/composio/scripts/verify_composio.sh
# Add --no-flair if you don't vibe with the surfer voice in the scripts
```

If any step feels weird, switch to Option 1 and let Claude do it. No shame, brah.

---

## 🌊 How To Trigger It (Once Installed)

Two surfaces, two interaction styles. Don't mix them up.

### Talking to **Claude Code** (the installer)
This is where you went during install. After install, you basically never come back here for Composio stuff unless you want to:
- **Reinstall / reconfigure** → "Reinstall Composio on Hermes" or "Change my Composio routing rules"
- **Debug** → "Composio stopped working on Hermes — what gives?"
- **Rotate the API key** → "Rotate my Composio key"

Claude Code auto-loads the skill any time you mention Composio + Hermes together. The skill's frontmatter description handles trigger detection — no `/slash` needed. If you *want* to force-load it: type `/hermes-composio` and Claude pulls the full reference into context.

### Talking to **Hermes** (the operator)
This is the daily driver. SSH into your Hermes host (or use `hermes chat` from wherever you usually do), then just *talk like a person*:

> "List my last 10 unread Gmail emails."
> *Hermes reads `composio_search_tools`, finds `GMAIL_LIST_MESSAGES`, calls it, returns a summary.*

> "Create a Linear ticket for that Slack thread we just discussed."
> *Hermes uses the bundled overlay, picks the right slug, asks you to confirm because it's a write op, then sends it.*

> "Connect my Notion workspace."
> *Hermes calls `composio_manage_connections action=connect`, prints an OAuth URL, you click it, done.*

> "Every morning at 8am, summarize new GitHub issues in repo X and post to Slack #engineering."
> *Hermes sets up the cron, schedules the Composio chain.*

**You don't say "use Composio".** The agent figures out *when* to use it based on what you asked for. That's the whole point. If you find yourself constantly saying "use Composio," something's wrong with the routing config — open Claude Code and say "audit my Composio routing on Hermes."

---

## 🧠 What's Actually Happening Under the Hood

For the curious:

- **Claude Code skill** (this repo) = the installer + operations manual. Lives in `~/.claude/skills/`.
- **Hermes-side skill** (`assets/hermes-composio-skill/`) = an overlay skill that ships into `~/.hermes/skills/composio/`. Teaches Hermes when to call Composio tools and how to route them.
- **Composio MCP server** = the actual tool surface. Hermes connects to `https://mcp.composio.dev/mcp` and Composio handles all the OAuth/auth/API-call mess for 1000+ SaaS tools.
- **Model router overlay** = if you have the [hermes-agent-specialist](https://github.com/Zelray/) `model-router` skill installed (separate skill), this skill plugs into it so reads go to Haiku, writes stay on Sonnet, image-prompt sub-steps go to your local Qwen. If you don't have model-router installed, no harm — all calls just run on whatever model Hermes is currently using.

---

## 📦 What's In The Box

| Path | What it does |
|---|---|
| `SKILL.md` | Claude Code skill entry point. Frontmatter, operating rules, file index. |
| `README.md` | The file you're reading. |
| `LICENSE` | MIT. Use it however. |
| `verification-checklist.md` | 7-section post-install verification — runs end-to-end. |
| `reference/api-key-setup.md` | Guided Composio signup + key paste + key verification. |
| `reference/hermes-install.md` | MCP install path (primary) + REST API fallback path. |
| `reference/routing-integration.md` | Sonnet/Haiku/Qwen routing via the existing `model-router` overlay. |
| `reference/tool-reference.md` | Sonnet-tuned descriptions of Composio's 4 meta-tools + slug naming patterns. |
| `reference/openclaw-appendix.md` | Install Composio on moltbot/clawdbot too (secondary use case). |
| `assets/hermes-composio-skill/SKILL.md` | The skill that gets copied into `~/.hermes/skills/composio/`. |
| `assets/hermes-composio-skill/scripts/verify_composio.sh` | One-shot health check. |
| `assets/hermes-composio-skill/scripts/setup_api_key.sh` | Interactive key onboarding. |

Both scripts respond to `--no-flair` if the surfer voice isn't your jam.

---

## 🛟 Troubleshooting

| Wipeout | Most likely cause | Fix |
|---|---|---|
| `hermes mcp list` doesn't show composio after install | `hermes mcp add` flags differ on your version | Run `hermes mcp add --help` on your Hermes box and match. Or just ask Claude Code to re-run install. |
| Hermes can't reach `backend.composio.dev` | Firewall / egress block on your Hermes host | Whitelist `*.composio.dev:443` or use the REST-via-skill fallback (see `reference/hermes-install.md` Path B). |
| `verify_composio.sh` returns HTTP 401 | Bad / revoked / typo'd key | Run `bash setup_api_key.sh --rotate` and paste a fresh one from [platform.composio.dev/settings](https://platform.composio.dev/settings). |
| `verify_composio.sh` complains about missing `jq` | jq not installed | `apt install jq` / `brew install jq`. The script falls back to grep but jq's cleaner. |
| OAuth toolkit connect hangs forever | You didn't click the auth URL in your browser | Click the URL Hermes printed, complete the OAuth, then tell Hermes "try again." |
| Hermes uses Sonnet even for `LIST_*` reads | `model-router` overlay isn't installed, or `composio_lookup` route isn't wired | Tell Claude Code: "audit my Composio routing on Hermes." |

---

## 🗺️ v2 Roadmap (Not In This Release)

- **Toolkit allowlist** — `skills.config.composio.allowed_toolkits` filtering which Composio toolkits Hermes even sees. Waiting on real usage data to pick the set.
- **Per-toolkit confirm rules** — granular "always confirm Salesforce writes, never bother me about Notion drafts."
- **Spend-aware route fallback** — when `daily_budget_usd` hits 80%, auto-downgrade Sonnet → Haiku for the rest of the day.
- **Native `tool_slugs_prefix` matcher** — currently the matcher only honors `keywords`; prefix-based routing is documented but commented out.
- **Cross-stack key rotation** — rotate Hermes + moltbot + any other agent stack with one command.

PRs welcome. File issues at https://github.com/Zelray/Hermes-Composio-Skill/issues.

---

## 🙏 Credits

- Composio tool surface and CLI examples adapted from the [moltbot/clawdbot](https://github.com/moltbot/moltbot) Composio plugin (MIT).
- Hermes Agent skill format from [Nous Research](https://hermes-agent.nousresearch.com).
- Sonnet-tuned tool descriptions, routing integration, install paths, and surfer voice: original to this skill.

---

🤙 **Drop in, send the line, catch the wave.** Aloha, brah.
