#!/usr/bin/env bash
set -euo pipefail

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
    jq -r '.message // empty' version-create.json 2>/dev/null || true
    echo
    jq '.' version-create.json 2>/dev/null || cat version-create.json
  else
    echo "No version-create.json was produced."
  fi
  echo "::endgroup::"
  exit 1
fi

VERSION_ID=$(jq -r '.result.SubscriberPackageVersionId' version-create.json)
echo "version_id=$VERSION_ID" >> "$GITHUB_OUTPUT"
