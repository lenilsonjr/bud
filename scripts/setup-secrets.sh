#!/usr/bin/env bash
# Set the five TestFlight secrets on a GitHub repo. Run once per repo — OR skip this entirely by
# defining ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_CONTENT / APPLE_TEAM_ID as GitHub ORG secrets, which
# every repo in the org inherits.
#
# Usage:
#   ASC_KEY_ID=... ASC_ISSUER_ID=... APPLE_TEAM_ID=... BUNDLE_ID_PREFIX=... \
#   ASC_KEY_P8=~/.appstoreconnect/private_keys/AuthKey_XXXX.p8 \
#   scripts/setup-secrets.sh <owner/repo>
set -euo pipefail
REPO="${1:?usage: setup-secrets.sh <owner/repo>}"
: "${ASC_KEY_ID:?set ASC_KEY_ID}"
: "${ASC_ISSUER_ID:?set ASC_ISSUER_ID}"
: "${APPLE_TEAM_ID:?set APPLE_TEAM_ID}"
: "${BUNDLE_ID_PREFIX:?set BUNDLE_ID_PREFIX}"
: "${ASC_KEY_P8:?set ASC_KEY_P8 to the path of your AuthKey_*.p8}"
[ -f "$ASC_KEY_P8" ] || { echo "no such .p8: $ASC_KEY_P8" >&2; exit 1; }

gh secret set ASC_KEY_ID       -R "$REPO" --body "$ASC_KEY_ID"
gh secret set ASC_ISSUER_ID    -R "$REPO" --body "$ASC_ISSUER_ID"
gh secret set APPLE_TEAM_ID    -R "$REPO" --body "$APPLE_TEAM_ID"
gh secret set BUNDLE_ID_PREFIX -R "$REPO" --body "$BUNDLE_ID_PREFIX"
base64 -i "$ASC_KEY_P8" | tr -d '\n' | gh secret set ASC_KEY_CONTENT -R "$REPO"

echo "Secrets set on $REPO:"
gh secret list -R "$REPO"
