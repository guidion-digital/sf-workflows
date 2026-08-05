#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/log.sh
source "$SCRIPT_DIR/lib/log.sh"

sf package install \
  --package "$VERSION_ID" \
  --target-org "$SF_USERNAME" \
  --wait 30 \
  --no-prompt
log_success "Installed package version $VERSION_ID into $SF_USERNAME"
