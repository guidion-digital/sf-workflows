#!/usr/bin/env bash
set -euo pipefail

sf package install \
  --package "$VERSION_ID" \
  --target-org "$SF_USERNAME" \
  --wait 30 \
  --no-prompt
