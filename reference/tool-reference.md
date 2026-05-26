# Composio Tool Reference (Sonnet-tuned)

> Use this file when constructing tool definitions, debugging tool calls, or explaining to the user what each Composio tool does. Descriptions are written to maximize Sonnet's tool-selection accuracy: concrete trigger language, explicit when-to-use, and clear when-not-to-use.

## The four logical tools

Composio exposes hundreds of concrete tool slugs (`GMAIL_SEND_EMAIL`, `GITHUB_CREATE_ISSUE`, etc.) plus four meta-tools that the agent calls. The four meta-tools are what Sonnet actually picks from:

| Tool name | Purpose | Sonnet calls it when… |
|---|---|---|
| `composio_search_tools` | Find candidate tool slugs by intent. | The user describes an outcome ("send a Slack message", "create a Linear ticket") but the agent doesn't yet know the exact slug. |
| `composio_execute_tool` | Run one tool slug with arguments. | The agent has a confirmed slug + arg set and the action should happen now. |
| `composio_multi_execute` | Run up to N tool calls in parallel. | The user asks for a multi-target action ("notify Slack and create a Linear ticket and email Bob"). |
| `composio_manage_connections` | Check / connect / disconnect toolkits. | The agent hits an auth error, OR the user asks to add/remove a toolkit, OR the agent needs to verify a toolkit is connected before calling its tools. |

## Sonnet-tuned tool descriptions

These are the descriptions to ship in `assets/hermes-composio-skill/SKILL.md`. Each one:
- Starts with a verb (Sonnet picks better when the description is action-first).
- Lists 2–3 concrete trigger phrases.
- Names the *opposite* tool to use (anti-routing hint).
- Specifies argument shape with one realistic example.

### `composio_search_tools`

```yaml
name: composio_search_tools
description: |
  Search Composio's tool catalog for a tool slug matching the user's intent.
  Call this BEFORE composio_execute_tool when you do not already know the exact
  slug. Returns up to `limit` matching tools with their slug, toolkit, and a one-line
  description.

  Use when the user says: "send a message in Slack", "create a doc in Notion",
  "log a Salesforce activity" — and you do not have the slug memorized.

  Do NOT use when: you already have a confirmed slug from a prior search in this
  conversation. Re-using a known slug is faster and cheaper. For checking whether
  a toolkit is *connected*, use composio_manage_connections, not search.
parameters:
  query:
    type: string
    description: Plain-English description of the desired action. Example "send email with attachment".
  toolkits:
    type: array
    items: string
    description: Optional filter by toolkit slug (gmail, slack, github). Lowercase.
  limit:
    type: integer
    default: 5
    description: Max results. Keep small (3–5) for prompt economy.
example:
  query: "create a new issue with labels"
  toolkits: ["github"]
  limit: 3
```

### `composio_execute_tool`

```yaml
name: composio_execute_tool
description: |
  Execute one Composio tool slug with its arguments. Returns the tool result
  (JSON) or an error. This is the "do the thing" call.

  Use when: you have a confirmed slug (from prior search or memory) and a full
  argument set, AND the user has implicitly or explicitly authorized the action.

  Do NOT use when:
    - The slug is uncertain — call composio_search_tools first.
    - The toolkit is not yet connected — call composio_manage_connections.
    - The action is destructive (delete/send-irreversible) and the user has not
      explicitly confirmed. Ask first.
    - You need to run 2+ actions at once — call composio_multi_execute.
parameters:
  tool_slug:
    type: string
    description: Exact uppercase slug. Example GMAIL_SEND_EMAIL.
  arguments:
    type: object
    description: Tool-specific argument object. Shape matches the slug's schema as returned by composio_search_tools.
example:
  tool_slug: GMAIL_SEND_EMAIL
  arguments:
    to: "bob@example.com"
    subject: "Confirming Tuesday 2pm"
    body: "Hi Bob, confirming our meeting for Tuesday at 2pm PT. — sent via Hermes"
```

### `composio_multi_execute`

```yaml
name: composio_multi_execute
description: |
  Execute up to 10 tool calls in parallel (Composio supports 50; the overlay caps
  to 10 by default for cost safety — see skills.config.composio.max_multi_execute_size).
  Returns an array of per-call results.

  Use when the user's single request spans multiple tools or multiple targets:
    - "Notify Slack and create a Linear ticket and email the author"
    - "Cross-post this announcement to Slack #general and Slack #product"
    - "Get my last 5 PRs from each of these 3 repos"

  Do NOT use when:
    - Calls have dependencies (output of A feeds into B). Use sequential
      composio_execute_tool calls instead.
    - Only one call is needed. Use composio_execute_tool.
    - More than 10 calls. Split into batches or raise max_multi_execute_size with
      user approval.
parameters:
  executions:
    type: array
    items:
      type: object
      properties:
        tool_slug: { type: string }
        arguments: { type: object }
example:
  executions:
    - tool_slug: GITHUB_CREATE_ISSUE
      arguments: { title: "Bug X", repo: "org/repo", body: "..." }
    - tool_slug: SLACK_SEND_MESSAGE
      arguments: { channel: "#dev", text: "Filed bug X" }
```

### `composio_manage_connections`

```yaml
name: composio_manage_connections
description: |
  Check, create, or remove a toolkit connection. A "connection" is the user's
  authenticated link to a SaaS account (Gmail OAuth, Slack OAuth, GitHub PAT).
  Each toolkit needs to be connected once before its tools become callable.

  Use when:
    - The user says "connect my Gmail", "link Slack", "remove GitHub connection".
    - A composio_execute_tool call returns an auth/connection error — call this
      to check status and re-trigger the connect flow.
    - You need to verify a toolkit is connected before promising the user an action.
parameters:
  action:
    type: string
    enum: [status, connect, disconnect, list]
    description: status = report state. connect = start OAuth flow (returns auth URL). disconnect = revoke. list = all connections.
  toolkits:
    type: array
    items: string
    description: Toolkit slugs. Omit with action=list.
example:
  action: connect
  toolkits: ["gmail"]
```

## Slug-naming conventions Sonnet should learn

| Pattern | Meaning | Example |
|---|---|---|
| `<TOOLKIT>_LIST_<RESOURCE>` | Read collection | `GMAIL_LIST_MESSAGES`, `GITHUB_LIST_ISSUES` |
| `<TOOLKIT>_GET_<RESOURCE>` | Read single item | `GMAIL_GET_MESSAGE`, `NOTION_GET_PAGE` |
| `<TOOLKIT>_SEARCH_<RESOURCE>` | Query with filters | `GMAIL_SEARCH_MESSAGES`, `LINEAR_SEARCH_ISSUES` |
| `<TOOLKIT>_CREATE_<RESOURCE>` | Write new | `GITHUB_CREATE_ISSUE`, `NOTION_CREATE_PAGE` |
| `<TOOLKIT>_UPDATE_<RESOURCE>` | Write existing | `LINEAR_UPDATE_ISSUE` |
| `<TOOLKIT>_SEND_<RESOURCE>` | Outbound message | `GMAIL_SEND_EMAIL`, `SLACK_SEND_MESSAGE` |
| `<TOOLKIT>_DELETE_<RESOURCE>` | Destructive | `GITHUB_DELETE_REPO` — always confirm |
| `<TOOLKIT>_REPLY_<RESOURCE>` | Threaded send | `GMAIL_REPLY_TO_THREAD`, `SLACK_REPLY_TO_THREAD` |

This prefix table feeds `skills.config.model-router.routes.*.tool_slugs_prefix` (see `routing-integration.md`). It also makes Sonnet's slug guessing more accurate when search results are ambiguous.

## Argument-quality checklist (for Sonnet before calling execute)

1. **Required fields present.** Check the tool's parameter schema from the prior search result.
2. **Recipients verified.** For email/message slugs, confirm the recipient address/channel is the one the user named — never autocomplete.
3. **Destructive ops confirmed.** Anything matching `DELETE_*`, `REVOKE_*`, `ARCHIVE_*` requires explicit user "yes" before execute.
4. **Idempotency awareness.** Composio does not deduplicate. If retrying, check the toolkit's response from the previous attempt before resending.

## Error handling cheat sheet

| Composio error | What to tell the user | What to do next |
|---|---|---|
| `unauthorized` (HTTP 401) | "Composio API key is invalid or revoked." | Rerun `api-key-setup.md` Step 4 verification. |
| `connection_not_found` for toolkit | "{Toolkit} is not connected yet — let me connect it." | Call `composio_manage_connections action=connect`. |
| `rate_limit` (HTTP 429) | "Composio rate limit hit." | Back off 30s, retry once. If recurring, recommend the user upgrade Composio plan. |
| `tool_not_found` | "That action isn't available in this Composio toolkit." | Call `composio_search_tools` with a broader query. |
| `invalid_arguments` | "Tool argument mismatch — let me re-check the schema." | Call `composio_search_tools` again to refresh the schema, then retry. |
