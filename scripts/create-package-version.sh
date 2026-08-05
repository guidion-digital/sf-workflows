#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/log.sh
source "$SCRIPT_DIR/lib/log.sh"

set +e
sf package version create \
  --package "$PACKAGE_NAME" \
  --target-dev-hub "$SF_DEVHUB_ALIAS" \
  --installation-key-bypass \
  --code-coverage \
  --wait 30 \
  --json > version-create.json
STATUS=$?
set -e

if [ "$STATUS" -ne 0 ] || [ ! -s version-create.json ] || [ "$(jq -r '.status' version-create.json)" != "0" ]; then
  echo "::error::Package version creation failed"
  echo "::group::sf package version create failure details"
  if [ -f version-create.json ]; then
    echo
    echo "---------- error message print ----------"
    echo
    jq -r '.message // empty' version-create.json 2>/dev/null || true
    echo
    echo "---------- full JSON payload ----------"
    echo
    jq '.' version-create.json 2>/dev/null || cat version-create.json
  else
    echo "No version-create.json was produced."
  fi
  echo "::endgroup::"
  exit 1
fi

VERSION_ID=$(jq -r '.result.SubscriberPackageVersionId' version-create.json)
log_success "Created package version: $VERSION_ID"
echo "version_id=$VERSION_ID" >> "$GITHUB_OUTPUT"
