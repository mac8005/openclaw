#!/usr/bin/env bash
# Setup TestFlight secrets for mac8005/openclaw
# Run once to copy signing secrets from your local machine to this repo.
#
# Prereqs: gh CLI authenticated as mac8005

set -euo pipefail

REPO="mac8005/openclaw"
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

ok()   { echo -e "${GREEN}✓ $*${NC}"; }
warn() { echo -e "${YELLOW}⚠ $*${NC}"; }
err()  { echo -e "${RED}✗ $*${NC}"; }

echo ""
echo "=== OpenClaw TestFlight Secrets Setup ==="
echo "Target: $REPO"
echo ""

# ── APPLE_TEAM_ID ──────────────────────────────────────────────────────────────
TEAM_ID=""
PROFILE_DIR="$HOME/Library/MobileDevice/Provisioning Profiles"
if [ -d "$PROFILE_DIR" ]; then
  LATEST=$(ls -t "$PROFILE_DIR"/*.mobileprovision 2>/dev/null | head -1)
  if [ -n "$LATEST" ]; then
    TEAM_ID=$(security cms -D -i "$LATEST" 2>/dev/null \
      | plutil -extract TeamIdentifier.0 raw - 2>/dev/null || true)
  fi
fi

if [ -z "$TEAM_ID" ]; then
  warn "Could not auto-detect Apple Team ID."
  echo "Find it at: https://developer.apple.com/account → Membership"
  printf "Enter Apple Team ID: "
  read -r TEAM_ID
fi
echo "$TEAM_ID" | gh secret set APPLE_TEAM_ID -R "$REPO"
ok "APPLE_TEAM_ID = $TEAM_ID"

# ── App Store Connect API Key ──────────────────────────────────────────────────
echo ""
echo "App Store Connect API Key"
echo "(same key you use for schwab-thinkorswim-t)"
echo ""

printf "Enter ASC Key ID (e.g. ABC123XYZ): "
read -r ASC_KEY_ID
echo "$ASC_KEY_ID" | gh secret set APPSTORE_API_KEY_ID -R "$REPO"
ok "APPSTORE_API_KEY_ID = $ASC_KEY_ID"

printf "Enter ASC Issuer ID (xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx): "
read -r ASC_ISSUER_ID
echo "$ASC_ISSUER_ID" | gh secret set APPSTORE_API_KEY_ISSUER_ID -R "$REPO"
ok "APPSTORE_API_KEY_ISSUER_ID"

# Try to find .p8 file automatically
P8_FILE=""
for loc in \
    "$HOME/Downloads/AuthKey_${ASC_KEY_ID}.p8" \
    "$HOME/Desktop/AuthKey_${ASC_KEY_ID}.p8" \
    "$HOME/Documents/AuthKey_${ASC_KEY_ID}.p8" \
    "$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8"; do
  if [ -f "$loc" ]; then
    P8_FILE="$loc"
    break
  fi
done

if [ -n "$P8_FILE" ]; then
  ok "Found p8 key at $P8_FILE"
else
  warn "Could not find AuthKey_${ASC_KEY_ID}.p8 automatically."
  printf "Enter path to .p8 file (drag & drop works): "
  read -r P8_FILE
  P8_FILE=$(echo "$P8_FILE" | tr -d "'\""  | xargs)
fi

if [ ! -f "$P8_FILE" ]; then
  err "File not found: $P8_FILE"
  exit 1
fi

base64 -i "$P8_FILE" | gh secret set APPSTORE_API_KEY_BASE64 -R "$REPO"
ok "APPSTORE_API_KEY_BASE64"

# ── Optional: custom bundle ID ─────────────────────────────────────────────────
echo ""
echo "Bundle ID (optional)"
echo "Default is 'ai.openclaw.ios' — register it in your App Store Connect first."
echo "Or use a custom one like 'macdevnet.openclaw'"
printf "Enter bundle ID (press Enter to skip): "
read -r BUNDLE_ID

if [ -n "$BUNDLE_ID" ]; then
  echo "$BUNDLE_ID" | gh secret set OPENCLAW_BUNDLE_ID -R "$REPO"
  ok "OPENCLAW_BUNDLE_ID = $BUNDLE_ID"
else
  warn "Skipped OPENCLAW_BUNDLE_ID — will use 'ai.openclaw.ios'"
  warn "Make sure that app exists in your App Store Connect before triggering the workflow."
fi

echo ""
echo "==================================="
ok "All secrets set for $REPO"
echo "==================================="
echo ""
echo "Next steps:"
echo "1. Create the app in App Store Connect (if it doesn't exist):"
echo "   https://appstoreconnect.apple.com → My Apps → + → New App"
echo "   Bundle ID: ${BUNDLE_ID:-ai.openclaw.ios}"
echo ""
echo "2. Trigger the workflow:"
echo "   gh workflow run testflight.yml -R $REPO"
echo ""
echo "3. Monitor at: https://github.com/$REPO/actions"
