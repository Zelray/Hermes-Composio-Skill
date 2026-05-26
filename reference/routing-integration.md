# Composio × Model Router Integration

> Use this file when deciding which model (Sonnet, Haiku, local Qwen, etc.) should handle a given Composio call. Sonnet is the user's **primary** model on Hermes; Haiku and Qwen are cost/speed delegates for narrower jobs.

## Core principle

Composio is an **action layer**, not a reasoning layer. The cost of a Composio call is almost entirely the LLM tokens around it (deciding which tool, building arguments, summarizing the result) — the HTTPS call itself is ~$0. So the routing question reduces to: *how much reasoning does this Composio call need?*

| Reasoning depth | Example user request | Right model | Why |
|---|---|---|---|
| **Low** — single read, well-shaped query | "List emails from the past 2 hours" | **Haiku** | One tool, fixed args, single-pass summary. Haiku handles it for ~1/15th the cost. |
| **Low** — list resources | "Show my open GitHub PRs in `repo-x`" | **Haiku** | Same shape. |
| **Medium** — single write, needs draft text | "Send Bob a confirmation email about the meeting" | **Sonnet** | Drafting a *good* email requires Sonnet-grade prose; Composio call itself is trivial. |
| **Medium** — multi-step coordinated action | "Create a Linear issue from this Slack thread and notify the author" | **Sonnet** | Two writes + cross-tool reasoning. Sonnet stays primary. |
| **High** — image prompt generation | "Generate three image prompts for the blog post draft I'm sending to Notion" | **local Qwen 4B** for the prompts, **Sonnet** for the Composio orchestration | Image prompt generation is the user's existing Qwen route; Composio glue stays on Sonnet. |
| **High** — long-running automation, branching logic | "Every morning at 7am, summarize new GitHub issues, post to Slack, and create Linear tickets for P0s" | **Sonnet** | Branching + judgment + cron scheduling. Worth the spend. |

## How this plugs into the existing `model-router` overlay

The user already has the `model-router` overlay installed (`hermes-agent-specialist/assets/model-router-skill/`). Composio routing is a new **route** in that table — not a separate router.

Run `hermes config get providers` first to find the real provider IDs and model IDs available on this Hermes install, then append to `~/.hermes/config.yaml` (replace every `TODO_*` placeholder):

```yaml
skills:
  config:
    model-router:
      routes:
        composio_lookup:
          intent: Read-only Composio lookup or listing
          keywords: ["list emails", "show issues", "fetch", "search composio", "find in"]
          # tool_slugs_prefix: v1.1 — not honored by current matcher. Leave commented.
          # tool_slugs_prefix: ["GMAIL_LIST", "GMAIL_GET", "GITHUB_LIST", "GITHUB_GET", "SLACK_LIST", "NOTION_LIST", "LINEAR_LIST"]
          provider: TODO_HAIKU_PROVIDER_ID
          model:    TODO_HAIKU_MODEL_ID
          command_mode: oneshot
          fallback_route: routine_chat

        composio_action:
          intent: Composio write/create/send action that needs drafted content
          keywords: ["send email", "create issue", "post message", "schedule meeting"]
          # tool_slugs_prefix: v1.1 — not honored by current matcher.
          # tool_slugs_prefix: ["GMAIL_SEND", "GMAIL_REPLY", "GITHUB_CREATE", "SLACK_SEND", "NOTION_CREATE", "LINEAR_CREATE"]
          provider: TODO_SONNET_PROVIDER_ID
          model:    TODO_SONNET_MODEL_ID
          command_mode: current_session
          fallback_route: routine_chat

        composio_image_prompt:
          intent: Generate image prompts then send/save via Composio
          keywords: ["image prompt", "midjourney prompt", "dalle prompt", "stable diffusion"]
          delegate_model: TODO_QWEN_LOCAL_MODEL_ID
          provider: TODO_SONNET_PROVIDER_ID
          model:    TODO_SONNET_MODEL_ID
          command_mode: current_session
          notes: "Qwen drafts the prompts; Sonnet drives the Composio call."
```

`tool_slugs_prefix` is **planned v1.1 overlay data**. The current `model-router` matcher works on `keywords` only. Listing the field above as a commented hint documents intent without breaking today's matcher.

## Decision flow for the live agent

```
User request mentions Composio-style action?
  │
  ├─ No → ignore this skill, defer to default routing.
  │
  └─ Yes
     │
     1. Search for matching tool: composio_search_tools(query=user_intent)
     2. Get back candidate slugs.
     3. Match slug prefix against composio_lookup / composio_action / composio_image_prompt.
     4. If match → switch / delegate / oneshot per command_mode.
     5. If no match → stay on current session model (Sonnet).
     6. Execute via composio_execute_tool or composio_multi_execute.
     7. Summarize result in user's chosen language.
```

The `assets/hermes-composio-skill/SKILL.md` encodes this flow as the live-agent instruction.

## What to label as native vs overlay (PM-facing distinction)

When discussing routing with the user, always make this clear:

| Behavior | Native to Hermes? | Configured where |
|---|---|---|
| Hermes calls MCP tools at all | **Native** | `hermes mcp add` |
| `delegation.*` for whole-subtask delegate model | **Native** | `~/.hermes/config.yaml` `delegation.*` |
| `auxiliary.*` slots for fixed Hermes-internal tasks | **Native** | `auxiliary.*` |
| Per-intent routing of *user* requests to Sonnet/Haiku/Qwen | **Overlay** (model-router skill) | `skills.config.model-router.routes.*` |
| Composio-slug-aware routing | **Overlay** (this skill, on top of model-router) | `skills.config.model-router.routes.composio_*` |

Never tell the user "Hermes natively routes Composio calls to Haiku." It does not. Only the overlay does.

## Cost guardrails

Add to `skills.config.composio`:

```yaml
skills:
  config:
    composio:
      max_multi_execute_size: 10     # cap parallel calls (Composio allows 50)
      confirm_before_write: true     # agent asks PM before SEND/REPLY/DELETE/ARCHIVE/REVOKE actions
      daily_budget_usd: 5.00         # advisory only (v1) — see implementation note below
```

`confirm_before_write: true` is the right default for a PM-driven agent. The user can flip it off per-session via a slash command once they trust a workflow.

**Implementation status of `daily_budget_usd` (v1):** This field is **advisory only** in v1 — the bundled Hermes-side skill reads it and surfaces an estimated burn in the per-call summary, but it does not auto-throttle or auto-downgrade routing. The "warn at 80% / auto-downgrade above 100%" behavior is on the v2 roadmap and requires either Composio billing telemetry or a Hermes-side LLM cost ledger that does not yet exist. Set the field today so the value is captured; do not assume it will block spend.

## Common rationalizations to push back on

| User says | Better answer |
|---|---|
| "Just route everything to Haiku to save money." | Haiku will draft worse emails and miss multi-step orchestration. Route by *task complexity*, not blanket savings. |
| "Sonnet is overkill for `LIST_MESSAGES`." | Agreed — that's why `composio_lookup` exists. But don't move *all* reads to Haiku; reads with downstream reasoning ("then summarize and decide") should stay on Sonnet. |
| "Let's use Qwen for everything since it's local." | Qwen 4B is great at *narrow generative tasks* (image prompts). It is not the right call for tool-use orchestration. |
| "We don't need delegation if model-router exists." | They serve different needs. `delegation.*` is for whole subtasks Hermes spawns internally. `model-router` is for user intent. Keep both. |

## v2 roadmap (not implemented in this skill)

- **Allowlist-driven tool surface.** `skills.config.composio.allowed_toolkits` filtering the search results returned to the model. Pending: user needs ~2–3 weeks to identify the allowlist set from actual usage logs.
- **Per-toolkit confirmation rules.** `confirm_before_write` granularity by toolkit (e.g. always confirm Salesforce writes; never confirm Notion drafts).
- **Spend-aware route fallback.** When daily_budget_usd hits 80%, auto-downgrade `composio_action` route from Sonnet to Haiku for the remainder of the day.
