#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/log.sh
source "$SCRIPT_DIR/lib/log.sh"

PACKAGE_NAME=$(jq -r '.packageDirectories[0].package' sfdx-project.json)
echo "package_name=$PACKAGE_NAME" >> "$GITHUB_OUTPUT"

NEXT_VERSION_NUMBER="${NEXT_VERSION}.NEXT"
jq --arg v "$NEXT_VERSION_NUMBER" '.packageDirectories[0].versionNumber = $v' sfdx-project.json > sfdx-project.json.tmp
mv sfdx-project.json.tmp sfdx-project.json
log_success "Patched sfdx-project.json versionNumber to $NEXT_VERSION_NUMBER"
echo "::group::sfdx-project.json"
cat sfdx-project.json
echo "::endgroup::"
