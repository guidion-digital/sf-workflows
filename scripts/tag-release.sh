#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/log.sh
source "$SCRIPT_DIR/lib/log.sh"

: "${PACKAGE_VERSION_FULL:?PACKAGE_VERSION_FULL is required}"
: "${EXPECTED_VERSION:?EXPECTED_VERSION is required}"

RESOLVED_3PART="${PACKAGE_VERSION_FULL%.*}"

if [ "$RESOLVED_3PART" != "$EXPECTED_VERSION" ]; then
  echo "::error::Version mismatch: computed $EXPECTED_VERSION but Salesforce created $PACKAGE_VERSION_FULL"
  exit 1
fi

TAG="v${PACKAGE_VERSION_FULL}"
git tag "$TAG"
git push origin "$TAG"
log_success "Tagged and pushed $TAG"
