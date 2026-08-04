#!/usr/bin/env bash
set -euo pipefail

PACKAGE_NAME=$(jq -r '.packageDirectories[0].package' sfdx-project.json)
echo "package_name=$PACKAGE_NAME" >> "$GITHUB_OUTPUT"

NEXT_VERSION_NUMBER="${NEXT_VERSION}.NEXT"
jq --arg v "$NEXT_VERSION_NUMBER" '.packageDirectories[0].versionNumber = $v' sfdx-project.json > sfdx-project.json.tmp
mv sfdx-project.json.tmp sfdx-project.json
echo "Patched sfdx-project.json:"
cat sfdx-project.json
