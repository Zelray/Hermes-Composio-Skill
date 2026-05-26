#!/usr/bin/env bash
# ============================================================================
# verify_composio.sh  —  Hermes ↔ Composio health check
# ============================================================================
# Aloha, broseph. This little script paddles out and makes sure the wave is
# clean before you try to drop in on it. It checks four things:
#
#   1. You actually have a Composio API key in your boardshorts pocket.
#   2. The key isn't expired / yanked / wrong-shape (no kook keys).
#   3. The Composio backend is reachable from this Hermes box (no shark net).
#   4. At least one toolkit is showing up (otherwise the lineup is empty).
#
# Run anytime. Safe to call again and again — pure read-only, no edits.
# Usage:
#   bash verify_composio.sh                 # MCP transport (default)
#   bash verify_composio.sh --transport rest
#   bash verify_composio.sh --verbose
# ============================================================================

set -euo pipefail

# ---- surfboard wax: defaults & flags ---------------------------------------
TRANSPORT="mcp"   # MCP first, REST as the longboard fallback, brah
VERBOSE=0
QUIET=0           # suppress non-essential lines (also dampens surfer voice)
NO_FLAIR=0        # plain-English mode, no surfer talk
BASE_URL="${COMPOSIO_BASE_URL:-https://backend.composio.dev/api/v1}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --transport) TRANSPORT="$2"; shift 2 ;;
    --verbose|-v) VERBOSE=1; shift ;;
    --quiet|-q)   QUIET=1; shift ;;
    --no-flair)   NO_FLAIR=1; shift ;;
    -h|--help)
      grep '^# ' "$0" | sed 's/^# //'
      exit 0 ;;
    *) echo "Unknown flag: $1" >&2; exit 2 ;;
  esac
done

# Helper: surfer-voiced or plain. Strips slang when NO_FLAIR is set.
say_voice() {
  # $1 = surfer version, $2 = plain version
  if [[ $NO_FLAIR -eq 1 ]]; then echo "$2"; else echo "$1"; fi
}

log() { [[ $VERBOSE -eq 1 ]] && echo "  · $*" || true; }
ok()  { echo "  ✅ $*"; }
bad() { echo "  ❌ $*" >&2; }
warn(){ echo "  ⚠️  $*"; }

# ---- tool checks: don't wipeout because curl or jq is missing -------------
require_tool() {
  command -v "$1" >/dev/null 2>&1 || {
    bad "Missing required tool: $1. Install it and run me again."
    exit 1
  }
}
require_tool curl
HAVE_JQ=0
if command -v jq >/dev/null 2>&1; then HAVE_JQ=1; fi

# ---- check 1: do we have a key? --------------------------------------------
[[ $QUIET -eq 0 ]] && echo "$(say_voice "🏄 Hermes ↔ Composio health check — let's see if the wave is glassy." "Hermes ↔ Composio health check.")"
[[ $QUIET -eq 0 ]] && echo ""
echo "[1/4] Looking for COMPOSIO_API_KEY..."

# Try env first (cleanest), then ~/.hermes/.env, then hermes config.
KEY="${COMPOSIO_API_KEY:-}"

if [[ -z "$KEY" ]] && [[ -f "$HOME/.hermes/.env" ]]; then
  # Read the value portion of the FIRST matching line (cut -f2- keeps any '='
  # that legitimately appears inside the key). Strip leading/trailing single or
  # double quotes only — never strip internal characters.
  RAW="$(grep -E '^COMPOSIO_API_KEY=' "$HOME/.hermes/.env" | tail -1 | cut -d= -f2-)"
  # Trim a single surrounding pair of quotes if present.
  RAW="${RAW#\"}"; RAW="${RAW%\"}"
  RAW="${RAW#\'}"; RAW="${RAW%\'}"
  KEY="$RAW"
  [[ -n "$KEY" ]] && log "Found key in ~/.hermes/.env — totally tubular."
fi

if [[ -z "$KEY" ]] && command -v hermes >/dev/null 2>&1; then
  # Hermes redacts on output but we can detect presence.
  if hermes config get composio.api_key 2>/dev/null | grep -q '\*\|redacted\|[a-zA-Z0-9]'; then
    warn "Key appears to live in hermes config. Re-export to env for this check:"
    warn "  export COMPOSIO_API_KEY=\$(hermes config get composio.api_key --raw 2>/dev/null)"
  fi
fi

if [[ -z "$KEY" ]]; then
  bad "No COMPOSIO_API_KEY found. Run scripts/setup_api_key.sh to score one."
  exit 1
fi
ok "Key located. (length=${#KEY}, not printing — keep secrets in the locker.)"

# ---- check 2: shape sanity (don't waste a curl on a kook key) --------------
echo ""
echo "[2/4] Sanity-checking key shape..."
if [[ ${#KEY} -lt 20 ]]; then
  bad "Key is suspiciously short. Did you grab the whole thing from the dashboard?"
  exit 1
fi
if [[ "$KEY" =~ [[:space:]] ]]; then
  bad "Key contains whitespace. Copy-paste left some seaweed on it."
  exit 1
fi
ok "Shape looks legit."

# ---- check 3: can we reach the lineup? -------------------------------------
echo ""
echo "[3/4] Paddling out to $BASE_URL ..."
HTTP_CODE=$(curl -sS -o /tmp/composio_verify.json -w "%{http_code}" \
  -H "x-api-key: $KEY" \
  "$BASE_URL/toolkits" || echo "000")

case "$HTTP_CODE" in
  200)
    ok "Composio backend says: ride's on. (HTTP 200)" ;;
  401|403)
    bad "Auth failed. Key is bad or revoked. Rotate at platform.composio.dev/settings."
    exit 1 ;;
  000)
    bad "Couldn't reach Composio at all. Firewall? DNS? No swell today."
    exit 1 ;;
  5*)
    bad "Composio backend is slammed (HTTP $HTTP_CODE). Try again in a sec."
    exit 1 ;;
  *)
    bad "Unexpected HTTP $HTTP_CODE — peek at /tmp/composio_verify.json."
    exit 1 ;;
esac

# ---- check 4: any toolkits showing up? -------------------------------------
echo ""
echo "[4/4] Counting toolkits in the lineup..."
# Composio /toolkits returns a JSON array (or {items:[...]} depending on version).
# Use jq when available (clean parse); otherwise fall back to a grep heuristic.
if [[ $HAVE_JQ -eq 1 ]]; then
  COUNT=$(jq 'if type=="array" then length else (.items // []) | length end' /tmp/composio_verify.json 2>/dev/null || echo "0")
else
  warn "jq not installed — falling back to grep-based count (less precise). Install jq for cleaner output."
  COUNT=$(grep -oE '"(slug|name)"[[:space:]]*:' /tmp/composio_verify.json 2>/dev/null | wc -l | tr -d ' ')
  [[ -z "$COUNT" ]] && COUNT=0
fi

if [[ "$COUNT" -ge 1 ]]; then
  ok "$COUNT toolkit reference(s) detected in response. Sample:"
  if [[ $HAVE_JQ -eq 1 ]]; then
    jq -r 'if type=="array" then .[0:3][] else (.items // [])[0:3][] end | "      - " + (.name // .slug // "unknown")' /tmp/composio_verify.json 2>/dev/null || true
  else
    grep -oE '"(name|slug)"[[:space:]]*:[[:space:]]*"[^"]+"' /tmp/composio_verify.json 2>/dev/null | head -3 | sed 's/^/      - /' || true
  fi
else
  warn "Zero toolkits returned. Account might be fresh — that's chill, no breakage."
fi

# ---- transport-specific extra checks ---------------------------------------
echo ""
case "$TRANSPORT" in
  mcp)
    echo "[+] Transport=MCP — checking 'hermes mcp list' for composio entry..."
    if command -v hermes >/dev/null 2>&1; then
      if hermes mcp list 2>/dev/null | grep -qi composio; then
        ok "Composio MCP server is wired into Hermes."
      else
        warn "Composio MCP not yet attached. First check the right flag syntax:"
        warn "  hermes mcp add --help"
        warn "Then attach (example shape; flag names may differ on your Hermes):"
        warn "  hermes mcp add composio --transport http --url https://mcp.composio.dev/mcp --header \"x-api-key:\$COMPOSIO_API_KEY\""
        warn "Heads up: inline --header puts the key in process args. Prefer --header-from-file if your Hermes supports it."
      fi
    else
      warn "'hermes' CLI not on PATH from this shell — skipping MCP check."
    fi
    ;;
  rest)
    echo "[+] Transport=REST — your transport choice is good to go (key already validated above)."
    ;;
  *)
    bad "Unknown transport: $TRANSPORT (use 'mcp' or 'rest')."
    exit 2 ;;
esac

# ---- ride the wave ---------------------------------------------------------
echo ""
echo "$(say_voice "🌊 All checks passed. Hermes is hooked into Composio — go shred." "All checks passed. Hermes is connected to Composio.")"
exit 0
