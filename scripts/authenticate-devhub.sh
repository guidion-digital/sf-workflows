#!/usr/bin/env bash
set -euo pipefail

printf '%s' "$SF_DEVHUB_CLIENT_KEY" | base64 -d > devhub-client-key.key
sf org login jwt \
  --instance-url "https://login.salesforce.com" \
  --username "$SF_DEVHUB_USERNAME" \
  --client-id "$SF_DEVHUB_CLIENT_ID" \
  --jwt-key-file devhub-client-key.key \
  --alias "$SF_DEVHUB_ALIAS"
