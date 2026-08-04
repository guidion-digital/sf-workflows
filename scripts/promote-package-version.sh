#!/usr/bin/env bash
set -euo pipefail

sf package version promote \
  --package "$VERSION_ID" \
  --target-dev-hub "$SF_DEVHUB_ALIAS" \
  --no-prompt
