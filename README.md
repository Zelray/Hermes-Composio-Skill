# hermes-composio — Claude Code skill

A Claude Code skill that adds [Composio](https://composio.dev) (1000+ SaaS tools via OAuth/API-key) to a Nous Research **Hermes Agent** install. Sonnet-tuned tool descriptions, model-router-aware routing (Sonnet primary, Haiku for cheap reads, local Qwen for image prompts), and a guided API-key onboarding for non-coders.

> **Target version:** Hermes Agent **0.14.0**. Verify with `hermes --version` before edits.

## Why this skill exists

A user running Sonnet on Hermes wants Hermes to take real action in Gmail, Slack, GitHub, Notion, Linear, etc. — not just talk about them. Composio is the cleanest way to do that without writing 30 separate OAuth integrations.

Hermes 0.14 supports MCP, so Composio's managed MCP server is the primary install path. A REST fallback is documented for air-gapped or firewalled environments.

## What's in this skill

| Path | Purpose |
|---|---|
| `SKILL.md` | Claude Code skill entry. Frontmatter (15 fields), audience/tone, operating rules, file index. |
| `README.md` | This file. Plain-English overview for the user. |
| `verification-checklist.md` | Step-by-step post-install verification. |
| `reference/api-key-setup.md` | Guided Composio signup + key paste + verification (PM-friendly). |
| `reference/hermes-install.md` | Install on Hermes — MCP primary, REST fallback. |
| `reference/routing-integration.md` | How Composio routes to Sonnet/Haiku/Qwen via the existing `model-router` overlay. |
| `reference/tool-reference.md` | Sonnet-tuned descriptions of the 4 Composio meta-tools + slug naming patterns. |
| `reference/openclaw-appendix.md` | Install Composio on the user's moltbot/clawdbot stack (secondary use case). |
| `assets/hermes-composio-skill/SKILL.md` | The **Hermes-side** skill, copied to `~/.hermes/skills/composio/`. |
| `assets/hermes-composio-skill/scripts/verify_composio.sh` | Health-check script with whimsical surfer comments. |
| `assets/hermes-composio-skill/scripts/setup_api_key.sh` | Interactive key onboarding with whimsical surfer comments. |

## Quick start

The user is a PM. Three lines of instruction:

1. **Check key.** `bash ~/.hermes/skills/composio/scripts/verify_composio.sh` — tells you in 3 seconds if a key is missing.
2. **Onboard if missing.** `bash ~/.hermes/skills/composio/scripts/setup_api_key.sh` — walks you through signup, key paste, and re-verify.
3. **Install.** Tell Claude: *"Install Composio on Hermes"* — Claude reads `reference/hermes-install.md` and proposes the smallest diff.

> **Voice / language note:** Both helper scripts default to a light surfer voice ("paddling out", "broseph", etc.). If you prefer plain English, or if the user reads English as a second language, append `--no-flair` to either script: `bash setup_api_key.sh --no-flair`. The technical behavior is identical.

## Routing in one sentence

Sonnet stays primary on Hermes; the bundled overlay routes Composio *reads* (list/get/search) to Haiku for ~15× cost savings, and routes *image-prompt-generation* sub-steps to the user's existing local Qwen 4B route. Sonnet handles the orchestration around both.

Full details: `reference/routing-integration.md`.

## v2 backlog (not in this release)

- Toolkit allowlist (`skills.config.composio.allowed_toolkits`) — user needs 2–3 weeks of usage data to pick the set.
- Per-toolkit `confirm_before_write` granularity.
- Spend-aware route fallback (auto-downgrade Sonnet→Haiku above daily budget).
- Cross-stack key rotation helper (Hermes + moltbot in one command).

## License

MIT. Original `composio_*` tool surface and CLI examples adapted from the moltbot/clawdbot Composio plugin (MIT). Sonnet-tuned descriptions, routing integration, and Hermes install paths are original to this skill.

## Repo

`https://github.com/<owner>/Hermes-Composio` (pushed at skill build time — see `CHANGELOG.md` once created).
