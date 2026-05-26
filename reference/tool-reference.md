# Composio Tool Reference (Sonnet-tuned)

> Use this file when constructing tool definitions, debugging tool calls, or explaining to the user what each Composio tool does. Descriptions are written to maximize Sonnet's tool-selection accuracy: concrete trigger language, explicit when-to-use, and clear when-not-to-use.

## The six meta-tools (Composio Tool Router, real surface)

> **Source:** Captured directly from `hermes mcp test composio` on a working Hermes 0.14 + Composio install on 2026-05-26. Composio's actual MCP surface differs from older Composio plugin READMEs (which described a 4-tool surface). The current tool set is six meta-tools — names are uppercase.

Composio exposes hundreds of concrete tool slugs (`GMAIL_SEND_EMAIL`, `GITHUB_CREATE_ISSUE`, etc.) plus six meta-tools that the agent picks from:

| Tool name | Purpose | Sonnet calls it when… |
|---|---|---|
| `COMPOSIO_SEARCH_TOOLS` | Find candidate tool slugs by intent. | The user describes an outcome ("send a Slack message", "create a Linear ticket") but the agent doesn't yet know the exact slug. |
| `COMPOSIO_GET_TOOL_SCHEMAS` | Fetch the JSON-schema input definition for one or more known slugs. | The agent has slug candidates from SEARCH_TOOLS and now needs the exact argument shape before calling MULTI_EXECUTE_TOOL. |
| `COMPOSIO_MULTI_EXECUTE_TOOL` | Run 1–N tool calls in parallel. | The agent has confirmed slug(s) + arg set(s) — handles both single calls and bulk. There is no separate "execute one" tool. |
| `COMPOSIO_MANAGE_CONNECTIONS` | Check / connect / disconnect toolkits. | The agent hits an auth error, OR the user asks to add/remove a toolkit, OR the agent needs to verify a toolkit is connected before calling its tools. |
| `COMPOSIO_REMOTE_BASH_TOOL` | Execute bash in Composio's remote sandbox. | The user asks for a one-off shell action on Composio-managed remote files (rare; mostly for advanced workflows). |
| `COMPOSIO_REMOTE_WORKBENCH` | Process remote files or script bulk tool executions in the Composio sandbox. | The user wants a multi-step file pipeline (download → transform → re-upload) without running it on the Hermes host. |

The standard tool-call sequence is **SEARCH_TOOLS → GET_TOOL_SCHEMAS → MULTI_EXECUTE_TOOL**, with MANAGE_CONNECTIONS as an out-of-band setup step. The REMOTE_BASH / REMOTE_WORKBENCH pair are sandboxed extras and not required for typical SaaS actions.

## Sonnet-tuned tool descriptions

These are the descriptions to ship in `assets/hermes-composio-skill/SKILL.md`. Each one:
- Starts with a verb (Sonnet picks better when the description is action-first).
- Lists 2–3 concrete trigger phrases.
- Names the *opposite* tool to use (anti-routing hint).
- Specifies argument shape with one realistic example.

### `COMPOSIO_SEARCH_TOOLS`

```yaml
name: COMPOSIO_SEARCH_TOOLS
description: |
  Search Composio's tool catalog for a tool slug matching the user's intent.
  Call this BEFORE COMPOSIO_MULTI_EXECUTE_TOOL when you do not already know the
  exact slug. Returns up to `limit` matching tools with their slug, toolkit,
  and a one-line description.

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

### `COMPOSIO_GET_TOOL_SCHEMAS`

```yaml
name: COMPOSIO_GET_TOOL_SCHEMAS
description: |
  Fetch the input JSON-schema for one or more known tool slugs. Call this after
  COMPOSIO_SEARCH_TOOLS narrows you to a candidate slug, but before
  COMPOSIO_MULTI_EXECUTE_TOOL, so you know the exact argument shape.

  Use when: you have slug candidate(s) from search but the schema is not in
  your context yet.

  Do NOT use when: you already executed this exact slug in this conversation
  and the schema is in your scrollback. Re-fetching is wasted tokens.
parameters:
  tool_slugs:
    type: array
    items: string
    description: List of uppercase tool slugs to fetch schemas for.
example:
  tool_slugs: ["GMAIL_SEND_EMAIL"]
```

### `COMPOSIO_MULTI_EXECUTE_TOOL`

```yaml
name: COMPOSIO_MULTI_EXECUTE_TOOL
description: |
  Execute 1–N tool calls in parallel. Composio supports up to 50; the overlay
  caps to skills.config.composio.max_multi_execute_size (default 10) for cost
  safety. Returns an array of per-call results.

  This is the single execution surface — there is no separate "execute one"
  meta-tool. For a single call, pass an `executions` list of length 1.

  Use when the user's request spans one or more tools:
    - Single: "Send an email to Bob confirming Tuesday." (executions length 1)
    - Multi-target: "Notify Slack and create a Linear ticket and email the author."
    - Cross-post: "Post this announcement to Slack #general and #product."
    - Fan-out: "Get my last 5 PRs from each of these 3 repos."

  Do NOT use when:
    - Calls have dependencies (output of A feeds into B). Sequence two calls
      instead — fan-out parallelism is for independent calls.
    - More than max_multi_execute_size calls. Split into batches or raise the
      cap with user approval.
parameters:
  executions:
    type: array
    items:
      type: object
      properties:
        tool_slug: { type: string }
        arguments: { type: object }
example_single:
  executions:
    - tool_slug: GMAIL_SEND_EMAIL
      arguments:
        to: "bob@example.com"
        subject: "Confirming Tuesday 2pm"
        body: "Hi Bob, confirming Tuesday 2pm PT. — sent via Hermes"
example_multi:
  executions:
    - tool_slug: GITHUB_CREATE_ISSUE
      arguments: { title: "Bug X", repo: "org/repo", body: "..." }
    - tool_slug: SLACK_SEND_MESSAGE
      arguments: { channel: "#dev", text: "Filed bug X" }
```

### `COMPOSIO_MANAGE_CONNECTIONS`

```yaml
name: COMPOSIO_MANAGE_CONNECTIONS
description: |
  Check, create, or remove a toolkit connection. A "connection" is the user's
  authenticated link to a SaaS account (Gmail OAuth, Slack OAuth, GitHub PAT).
  Each toolkit needs to be connected once before its tools become callable.

  Use when:
    - The user says "connect my Gmail", "link Slack", "remove GitHub connection".
    - A COMPOSIO_MULTI_EXECUTE_TOOL call returns an auth/connection error — call
      this to check status and re-trigger the connect flow.
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

### `COMPOSIO_REMOTE_BASH_TOOL` (advanced)

```yaml
name: COMPOSIO_REMOTE_BASH_TOOL
description: |
  Execute a bash command in Composio's REMOTE sandbox. Use only for file
  operations on Composio-managed remote files. Not for general system
  administration — for that, use the Hermes host directly.

  Use when: the user explicitly asks to manipulate files inside Composio's
  workbench environment.

  Do NOT use when: the action belongs on the Hermes host or on the user's
  local machine. The remote sandbox is ephemeral.
parameters:
  command:
    type: string
    description: Bash command line to run in the remote sandbox.
```

### `COMPOSIO_REMOTE_WORKBENCH` (advanced)

```yaml
name: COMPOSIO_REMOTE_WORKBENCH
description: |
  Process remote files or script bulk tool execution in Composio's sandbox.
  Higher-level than REMOTE_BASH_TOOL — accepts a workflow description and
  orchestrates the file pipeline.

  Use when: the user asks for a multi-step file pipeline (download a Google
  Drive file → transform → upload to Notion) and wants it to run on
  Composio's infra instead of the Hermes host.

  Do NOT use when: the workflow can be expressed as 2–3 MULTI_EXECUTE_TOOL
  calls. The workbench is for complex pipelines, not simple chains.
parameters:
  workflow:
    type: object
    description: Workflow spec (consult COMPOSIO_GET_TOOL_SCHEMAS for the exact shape).
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
| `unauthorized` (HTTP 401) — generic | "Composio API key is invalid or revoked." | Rerun `api-key-setup.md` Step 4 verification. |
| `Failed to fetch API key information from DB` (HTTP 401 code 10401 / HTTP 500 code 809) | "Composio's backend is propagating your new key. Give it 5 minutes." | Wait 5 min. If still failing, regenerate the key. This error is most common right after key creation. |
| `connection_not_found` for toolkit | "{Toolkit} is not connected yet — let me connect it." | Call `COMPOSIO_MANAGE_CONNECTIONS action=connect`. |
| `rate_limit` (HTTP 429) | "Composio rate limit hit." | Back off 30s, retry once. If recurring, recommend the user upgrade Composio plan. |
| `tool_not_found` | "That action isn't available in this Composio toolkit." | Call `COMPOSIO_SEARCH_TOOLS` with a broader query. |
| `invalid_arguments` | "Tool argument mismatch — let me re-check the schema." | Call `COMPOSIO_GET_TOOL_SCHEMAS` for the slug, then retry. |
| `This endpoint is no longer available. Please upgrade to v3 APIs.` (HTTP 410) | "Old Composio API endpoint — we should be on v3." | Replace `/api/v1/...` with `/api/v3/...` in any curl probes. The MCP path is unaffected. |
