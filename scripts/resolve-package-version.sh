#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/log.sh
source "$SCRIPT_DIR/lib/log.sh"

: "${VERSION_ID:?VERSION_ID is required}"
: "${SF_DEVHUB_ALIAS:?SF_DEVHUB_ALIAS is required}"

QUERY_RESULT=$(sf data query --use-tooling-api \
  --target-org "$SF_DEVHUB_ALIAS" \
  --query "SELECT MajorVersion, MinorVersion, PatchVersion, BuildNumber FROM Package2Version WHERE SubscriberPackageVersionId='${VERSION_ID}'" \
  --json)

TOTAL_SIZE=$(printf '%s' "$QUERY_RESULT" | jq -r '.result.totalSize // 0')
if [ "$TOTAL_SIZE" -eq 0 ]; then
  echo "::error::No Package2Version found for SubscriberPackageVersionId '${VERSION_ID}'"
  exit 1
fi

MAJOR=$(printf '%s' "$QUERY_RESULT" | jq -r '.result.records[0].MajorVersion')
MINOR=$(printf '%s' "$QUERY_RESULT" | jq -r '.result.records[0].MinorVersion')
PATCH=$(printf '%s' "$QUERY_RESULT" | jq -r '.result.records[0].PatchVersion')
BUILD=$(printf '%s' "$QUERY_RESULT" | jq -r '.result.records[0].BuildNumber')

for part_name in MAJOR MINOR PATCH BUILD; do
  part="${!part_name}"
  if [[ ! "$part" =~ ^[0-9]+$ ]]; then
    echo "::error::Invalid $part_name '$part' from Package2Version query for '${VERSION_ID}'"
    exit 1
  fi
done

PACKAGE_VERSION="${MAJOR}.${MINOR}.${PATCH}"
PACKAGE_VERSION_FULL="${MAJOR}.${MINOR}.${PATCH}.${BUILD}"

log_success "Resolved package version: $PACKAGE_VERSION_FULL"
echo "package_version=$PACKAGE_VERSION" >> "$GITHUB_OUTPUT"
echo "package_version_full=$PACKAGE_VERSION_FULL" >> "$GITHUB_OUTPUT"
