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
  echo "::error::Package version creation failed, see the dumped payload below"
  exit 1
fi

VERSION_ID=$(jq -r '.result.SubscriberPackageVersionId' version-create.json)
echo "version_id=$VERSION_ID" >> "$GITHUB_OUTPUT"
