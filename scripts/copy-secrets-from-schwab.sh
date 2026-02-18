#!/usr/bin/env bash
# Copies the 4 required TestFlight secrets from mac8005/schwab-thinkorswim-t
# to mac8005/openclaw, fully automated with no manual input.
#
# How it works:
#   1. Stores your local gh token as a temp secret (GH_PAT) in schwab
#   2. Creates a temp workflow in schwab that reads its own secrets and
#      gh-secret-sets them in openclaw using that PAT
#   3. Triggers and waits for the workflow
#   4. Deletes the temp workflow file and GH_PAT secret
#
# Prereqs: gh CLI authenticated as mac8005

set -euo pipefail

SOURCE="mac8005/schwab-thinkorswim-t"
DEST="mac8005/openclaw"
WORKFLOW_FILE=".github/workflows/_copy-secrets-temp.yml"
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ok()   { echo -e "${GREEN}✓ $*${NC}"; }
step() { echo -e "${YELLOW}→ $*${NC}"; }

cleanup() {
  step "Cleaning up temporary resources..."
  # Delete temp workflow file
  SHA=$(gh api "repos/$SOURCE/contents/$WORKFLOW_FILE" --jq '.sha' 2>/dev/null || true)
  if [ -n "$SHA" ]; then
    gh api --method DELETE "repos/$SOURCE/contents/$WORKFLOW_FILE" \
      -f message="chore: remove temp copy-secrets workflow [skip ci]" \
      -f sha="$SHA" 2>/dev/null || true
    ok "Deleted temp workflow from $SOURCE"
  fi
  # Delete GH_PAT secret from source
  gh secret delete GH_PAT -R "$SOURCE" 2>/dev/null || true
  ok "Deleted GH_PAT secret from $SOURCE"
}
trap cleanup EXIT

echo ""
echo "=== Copy TestFlight Secrets: schwab → openclaw ==="
echo ""

# ── 1. Store local gh token as GH_PAT in source repo ──────────────────────────
step "Storing local gh token as temporary GH_PAT in $SOURCE..."
gh auth token | gh secret set GH_PAT -R "$SOURCE"
ok "GH_PAT secret set"

# ── 2. Create the temp copy workflow ──────────────────────────────────────────
step "Creating temporary copy-secrets workflow in $SOURCE..."

WORKFLOW_CONTENT=$(cat <<'YAML'
name: _Copy Secrets to OpenClaw (temp)
on:
  workflow_dispatch:
jobs:
  copy:
    runs-on: ubuntu-latest
    steps:
      - name: Copy secrets to mac8005/openclaw
        env:
          GH_TOKEN: ${{ secrets.GH_PAT }}
          APPLE_TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}
          APPSTORE_API_KEY_ID: ${{ secrets.APPSTORE_API_KEY_ID }}
          APPSTORE_API_KEY_ISSUER_ID: ${{ secrets.APPSTORE_API_KEY_ISSUER_ID }}
          APPSTORE_API_KEY_BASE64: ${{ secrets.APPSTORE_API_KEY_BASE64 }}
        run: |
          printf '%s' "$APPLE_TEAM_ID"           | gh secret set APPLE_TEAM_ID           -R mac8005/openclaw
          printf '%s' "$APPSTORE_API_KEY_ID"      | gh secret set APPSTORE_API_KEY_ID      -R mac8005/openclaw
          printf '%s' "$APPSTORE_API_KEY_ISSUER_ID" | gh secret set APPSTORE_API_KEY_ISSUER_ID -R mac8005/openclaw
          printf '%s' "$APPSTORE_API_KEY_BASE64"  | gh secret set APPSTORE_API_KEY_BASE64  -R mac8005/openclaw
          echo "✓ All 4 secrets copied to mac8005/openclaw"
YAML
)

ENCODED=$(printf '%s' "$WORKFLOW_CONTENT" | base64)
gh api --method PUT "repos/$SOURCE/contents/$WORKFLOW_FILE" \
  -f message="chore: add temp copy-secrets workflow [skip ci]" \
  -f "content=$ENCODED" > /dev/null
ok "Temp workflow created"

# ── 3. Trigger the workflow ────────────────────────────────────────────────────
step "Triggering workflow..."
sleep 3  # Give GitHub a moment to index the new workflow file
gh workflow run "_copy-secrets-temp.yml" -R "$SOURCE"
ok "Workflow triggered"

# ── 4. Wait for it to complete ─────────────────────────────────────────────────
step "Waiting for workflow to finish..."
sleep 8  # Let the run appear in the API

RUN_ID=$(gh run list -R "$SOURCE" \
  --workflow "_copy-secrets-temp.yml" \
  --limit 1 \
  --json databaseId \
  --jq '.[0].databaseId')

if [ -z "$RUN_ID" ]; then
  echo "Could not get run ID — check https://github.com/$SOURCE/actions manually."
  exit 1
fi

gh run watch "$RUN_ID" -R "$SOURCE" --exit-status
ok "Workflow completed successfully"

# ── 5. Verify ─────────────────────────────────────────────────────────────────
echo ""
step "Secrets now set in $DEST:"
gh secret list -R "$DEST"

echo ""
echo "================================================"
ok "Done! Secrets copied to $DEST"
echo "================================================"
echo ""
echo "Next: create the app in App Store Connect (bundle ID: ai.openclaw.ios)"
echo "Then trigger: gh workflow run testflight.yml -R $DEST"
