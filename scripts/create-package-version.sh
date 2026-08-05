#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/log.sh
source "$SCRIPT_DIR/lib/log.sh"

DEFINITION_FILE="${DEFINITION_FILE:-config/project-scratch-def.json}"

if [ ! -f "$DEFINITION_FILE" ]; then
  echo "::error::Missing package definition file: $DEFINITION_FILE"
  echo "Commit a Salesforce scratch/packaging org definition at that path (or set DEFINITION_FILE)."
  exit 1
fi

echo "::group::Package version create definition file ($DEFINITION_FILE)"
jq '.' "$DEFINITION_FILE" 2>/dev/null || cat "$DEFINITION_FILE"
echo "::endgroup::"

set +e
sf package version create \
  --package "$PACKAGE_NAME" \
  --target-dev-hub "$SF_DEVHUB_ALIAS" \
  --definition-file "$DEFINITION_FILE" \
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
    echo "---------- error message readable print ----------"
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
