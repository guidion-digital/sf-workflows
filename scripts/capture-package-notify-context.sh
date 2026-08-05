#!/usr/bin/env bash
# Capture truncated package-version-create error text for Slack notify job outputs.
set -euo pipefail

ERROR_SUMMARY=""

if [ -f version-create.json ]; then
  RAW_MESSAGE=$(jq -r '.message // empty' version-create.json 2>/dev/null || true)
  if [ -n "$RAW_MESSAGE" ]; then
    ERROR_SUMMARY=$(printf '%.1500s' "$RAW_MESSAGE")
  fi
fi

{
  echo "error_summary<<EOF"
  printf '%s\n' "$ERROR_SUMMARY"
  echo "EOF"
} >> "$GITHUB_OUTPUT"
