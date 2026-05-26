#!/usr/bin/env bash
# ============================================================================
# setup_api_key.sh  —  guided Composio API key onboarding
# ============================================================================
# Sup broseph. This is the bunny-slope version of getting Hermes hooked into
# Composio. You'll:
#   1. Open a browser tab (we'll print the URL).
#   2. Make a free Composio account & generate one secret string.
#   3. Paste it here when prompted.
#   4. We write it safe to ~/.hermes/.env (chmod 600, no leaks bro).
#   5. We run a quick paddle-out via verify_composio.sh to make sure it works.
#
# Re-runnable. If a key already exists, we refuse to overwrite unless you
# pass --rotate (so you don't kook your own setup on a typo).
#
# Usage:
#   bash setup_api_key.sh                 # fresh setup
#   bash setup_api_key.sh --rotate        # replace existing key
#   bash setup_api_key.sh --quiet         # less surfer talk, same result
# ============================================================================

set -euo pipefail

ROTATE=0
QUIET=0
NO_FLAIR=0
ENV_FILE="${HERMES_HOME:-$HOME/.hermes}/.env"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --rotate)   ROTATE=1; shift ;;
    --quiet|-q) QUIET=1; shift ;;
    --no-flair) NO_FLAIR=1; shift ;;
    -h|--help)
      grep '^# ' "$0" | sed 's/^# //'
      exit 0 ;;
    *) echo "Unknown flag: $1" >&2; exit 2 ;;
  esac
done

say() { [[ $QUIET -eq 0 ]] && echo "$@" || true; }
voice() { [[ $NO_FLAIR -eq 1 ]] && echo "$2" || echo "$1"; }

# ---- 0: ensure ~/.hermes exists --------------------------------------------
mkdir -p "$(dirname "$ENV_FILE")"

# ---- 1: detect existing key ------------------------------------------------
EXISTING=""
if [[ -f "$ENV_FILE" ]]; then
  EXISTING="$(grep -E '^COMPOSIO_API_KEY=' "$ENV_FILE" | tail -1 | cut -d= -f2- || true)"
fi

if [[ -n "$EXISTING" ]] && [[ $ROTATE -eq 0 ]]; then
  say "🏖  Key already chilling in $ENV_FILE. Bail or rotate, bro:"
  say "    bash setup_api_key.sh --rotate"
  exit 0
fi

# ---- 2: surf school intro --------------------------------------------------
say ""
say "🏄  Composio onboarding — about 3 minutes, no wax required."
say ""
say "  Step A. Make a free Composio account (skip if you have one):"
say "          👉  https://platform.composio.dev/signup"
say ""
say "  Step B. Generate an API key:"
say "          👉  https://platform.composio.dev/settings"
say "          Name it: hermes-\$(hostname)   (so future-you knows which board it is)"
say "          Copy the value. It starts with 'ck_' or similar."
say ""

# ---- 3: prompt for the key (silent, no echo) -------------------------------
KEY=""
ATTEMPTS=0
while [[ -z "$KEY" && $ATTEMPTS -lt 3 ]]; do
  ATTEMPTS=$((ATTEMPTS+1))
  # -s = silent so the key doesn't paint itself on the screen
  read -r -s -p "  Paste your Composio API key (input hidden): " RAW_KEY
  echo ""
  # Strip only leading/trailing whitespace; do NOT delete internal spaces.
  KEY="$(printf '%s' "$RAW_KEY" | awk '{$1=$1; print}')"
  if [[ "$KEY" != "$RAW_KEY" ]]; then
    say "  ℹ️   Trimmed surrounding whitespace from the key."
  fi
  if [[ ${#KEY} -lt 20 ]]; then
    say "$(voice "  ❌  Too short to be real. Try again, broseph." "  ❌  Key is too short. Please paste the full value from the Composio dashboard.")"
    KEY=""
  fi
done

if [[ -z "$KEY" ]]; then
  say ""
  say "  No key after 3 tries — bailing. Run me again when you've got one."
  exit 1
fi

# ---- 4: write it safe ------------------------------------------------------
# Rotate = strip any old line, then append fresh.
if [[ -f "$ENV_FILE" ]]; then
  TMP="${ENV_FILE}.tmp.$$"
  grep -v '^COMPOSIO_API_KEY=' "$ENV_FILE" > "$TMP" || true
  echo "COMPOSIO_API_KEY=$KEY" >> "$TMP"
  mv "$TMP" "$ENV_FILE"
else
  echo "COMPOSIO_API_KEY=$KEY" > "$ENV_FILE"
fi
chmod 600 "$ENV_FILE"   # locker locked, brah
say ""
say "  ✅  Key stashed in $ENV_FILE (chmod 600)."

# ---- 5: paddle-out test -----------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -x "$SCRIPT_DIR/verify_composio.sh" ]]; then
  say ""
  say "  🌊  Quick paddle-out via verify_composio.sh ..."
  # Export for the subprocess; don't pollute the user's shell permanently.
  COMPOSIO_API_KEY="$KEY" bash "$SCRIPT_DIR/verify_composio.sh" --quiet || {
    say ""
    say "  ⚠️  Verification didn't return clean. Key is saved, but something's off."
    say "      Run:  bash $SCRIPT_DIR/verify_composio.sh --verbose"
    exit 1
  }
else
  say ""
  say "  ℹ️   verify_composio.sh not next to me — skipping live check."
fi

# ---- 6: shake of stoke ------------------------------------------------------
say ""
say "🤙  All set. Restart Hermes so it picks up the new env:"
say "       systemctl restart hermes      # or your usual restart move"
say ""
say "    Then try:"
say "       hermes chat -q 'Connect my Gmail via Composio.'"
say ""
say "    Catch ya in the lineup."
