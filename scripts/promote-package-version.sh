#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/log.sh
source "$SCRIPT_DIR/lib/log.sh"

sf package version promote \
  --package "$VERSION_ID" \
  --target-dev-hub "$SF_DEVHUB_ALIAS" \
  --no-prompt
log_success "Promoted package version: $VERSION_ID"
