#!/usr/bin/env bash
set -euo pipefail

echo "Authenticating to target Salesforce org..."
printf '%s' "$SF_CLIENT_KEY" | base64 -d > target-client-key.key
sf org login jwt \
  --instance-url "${SF_LOGIN_URL:-https://login.salesforce.com}" \
  --username "$SF_USERNAME" \
  --client-id "$SF_CLIENT_ID" \
  --jwt-key-file target-client-key.key \
  --alias target
