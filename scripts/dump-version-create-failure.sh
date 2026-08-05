#!/usr/bin/env bash
set -euo pipefail

DEFINITION_FILE="${DEFINITION_FILE:-config/project-scratch-def.json}"

echo "::group::Raw 'sf package version create' output"
if [ -f version-create.json ]; then
  jq '.' version-create.json 2>/dev/null || cat version-create.json
else
  echo "No version-create.json was produced."
fi
echo "::endgroup::"

echo "::group::Package definition file ($DEFINITION_FILE)"
if [ -f "$DEFINITION_FILE" ]; then
  jq '.' "$DEFINITION_FILE" 2>/dev/null || cat "$DEFINITION_FILE"
else
  echo "Definition file not found: $DEFINITION_FILE"
fi
echo "::endgroup::"
