#!/usr/bin/env bash
set -euo pipefail

echo "::group::Raw 'sf package version create' output"
if [ -f version-create.json ]; then
  jq '.' version-create.json 2>/dev/null || cat version-create.json
else
  echo "No version-create.json was produced."
fi
echo "::endgroup::"
