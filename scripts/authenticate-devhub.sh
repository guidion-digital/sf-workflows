#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/log.sh
source "$SCRIPT_DIR/lib/log.sh"

log_step "Authenticating to Salesforce DevHub..."
printf '%s' "$SF_DEVHUB_CLIENT_KEY" | base64 -d > devhub-client-key.key
sf org login jwt \
  --instance-url "https://login.salesforce.com" \
  --username "$SF_DEVHUB_USERNAME" \
  --client-id "$SF_DEVHUB_CLIENT_ID" \
  --jwt-key-file devhub-client-key.key \
  --alias "$SF_DEVHUB_ALIAS"
log_success "Authenticated DevHub: $SF_DEVHUB_USERNAME (alias $SF_DEVHUB_ALIAS)"
