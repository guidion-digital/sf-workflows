#!/usr/bin/env bash
# Enqueue a package install (--wait 0) and poll until SUCCESS / ERROR / timeout.
# Do not trust `sf package install --wait N` exit codes: the CLI can exit 0 while
# status is still IN_PROGRESS after the wait window.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/log.sh
source "$SCRIPT_DIR/lib/log.sh"

: "${VERSION_ID:?VERSION_ID is required}"
: "${SF_USERNAME:?SF_USERNAME is required}"

SF_BASE_URL="${SF_BASE_URL:-}"
POLL_INTERVAL_SECONDS="${POLL_INTERVAL_SECONDS:-30}"
TIMEOUT_MINUTES="${TIMEOUT_MINUTES:-90}"
TIMEOUT_SECONDS=$((TIMEOUT_MINUTES * 60))
INSTALL_JSON="package-install.json"
REPORT_JSON="package-install-report.json"

emit_output() {
  local key="$1"
  local value="$2"
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    echo "${key}=${value}" >> "$GITHUB_OUTPUT"
  fi
}

format_elapsed_minutes() {
  local elapsed_seconds="$1"
  echo $((elapsed_seconds / 60))
}

deploy_status_url() {
  local request_id="$1"
  printf '%s/lightning/setup/DeployStatus/page?address=%%2Fchangemgmt%%2FmonitorDeploymentsDetails.apexp%%3FasyncId%%3D%s' \
    "$SF_BASE_URL" "$request_id"
}

log_step "Enqueue package install for $VERSION_ID into $SF_USERNAME"

set +e
sf package install \
  --package "$VERSION_ID" \
  --target-org "$SF_USERNAME" \
  --wait 0 \
  --json \
  --no-prompt > "$INSTALL_JSON"
INSTALL_EXIT=$?
set -e

if [ "$INSTALL_EXIT" -ne 0 ] || [ ! -s "$INSTALL_JSON" ] || [ "$(jq -r '.status' "$INSTALL_JSON")" != "0" ]; then
  echo "::error::Failed to enqueue package install for $VERSION_ID"
  echo "::group::sf package install failure details"
  if [ -f "$INSTALL_JSON" ]; then
    jq '.' "$INSTALL_JSON" 2>/dev/null || cat "$INSTALL_JSON"
  else
    echo "No $INSTALL_JSON was produced."
  fi
  echo "::endgroup::"
  exit 1
fi

REQUEST_ID=$(jq -r '.result.Id // .result.id // empty' "$INSTALL_JSON")
INSTALL_STATUS=$(jq -r '.result.Status // .result.status // empty' "$INSTALL_JSON")

if [ -z "$REQUEST_ID" ]; then
  echo "::error::Package install enqueue succeeded but no request Id was returned"
  jq '.' "$INSTALL_JSON" 2>/dev/null || cat "$INSTALL_JSON"
  exit 1
fi

emit_output "install_request_id" "$REQUEST_ID"
if [ -n "$SF_BASE_URL" ]; then
  emit_output "sf_base_url" "$SF_BASE_URL"
fi

log_notice "Package install request Id: $REQUEST_ID (initial status: ${INSTALL_STATUS:-unknown})"
echo "Poll with: sf package install report --request-id $REQUEST_ID --target-org $SF_USERNAME --json"

if [ -n "$SF_BASE_URL" ]; then
  TRACK_URL="$(deploy_status_url "$REQUEST_ID")"
  echo "Track in Salesforce: $TRACK_URL"
else
  echo "SF_BASE_URL not set; skipping DeployStatus tracking link"
fi

if [ "$INSTALL_STATUS" = "SUCCESS" ]; then
  log_success "Installed package version $VERSION_ID into $SF_USERNAME"
  exit 0
fi

if [ "$INSTALL_STATUS" = "ERROR" ]; then
  echo "::error::Package install failed immediately (request Id: $REQUEST_ID)"
  echo "::group::package install error details"
  jq '.' "$INSTALL_JSON" 2>/dev/null || cat "$INSTALL_JSON"
  echo "::endgroup::"
  exit 1
fi

START_EPOCH=$(date +%s)

while true; do
  NOW_EPOCH=$(date +%s)
  ELAPSED_SECONDS=$((NOW_EPOCH - START_EPOCH))
  ELAPSED_MINUTES="$(format_elapsed_minutes "$ELAPSED_SECONDS")"

  if [ "$ELAPSED_SECONDS" -ge "$TIMEOUT_SECONDS" ]; then
    echo "::error::Package install timed out after ${TIMEOUT_MINUTES}m still ${INSTALL_STATUS:-IN_PROGRESS} (request Id: $REQUEST_ID)"
    exit 1
  fi

  sleep "$POLL_INTERVAL_SECONDS"

  set +e
  sf package install report \
    --request-id "$REQUEST_ID" \
    --target-org "$SF_USERNAME" \
    --json > "$REPORT_JSON"
  REPORT_EXIT=$?
  set -e

  if [ "$REPORT_EXIT" -ne 0 ] || [ ! -s "$REPORT_JSON" ] || [ "$(jq -r '.status' "$REPORT_JSON")" != "0" ]; then
    echo "::error::Failed to poll package install report for request Id $REQUEST_ID"
    echo "::group::sf package install report failure details"
    if [ -f "$REPORT_JSON" ]; then
      jq '.' "$REPORT_JSON" 2>/dev/null || cat "$REPORT_JSON"
    else
      echo "No $REPORT_JSON was produced."
    fi
    echo "::endgroup::"
    exit 1
  fi

  INSTALL_STATUS=$(jq -r '.result.Status // .result.status // empty' "$REPORT_JSON")
  NOW_EPOCH=$(date +%s)
  ELAPSED_SECONDS=$((NOW_EPOCH - START_EPOCH))
  ELAPSED_MINUTES="$(format_elapsed_minutes "$ELAPSED_SECONDS")"

  echo "Install status: ${INSTALL_STATUS:-unknown} (${ELAPSED_MINUTES}m elapsed / ${TIMEOUT_MINUTES}m timeout)"

  case "$INSTALL_STATUS" in
    SUCCESS)
      log_success "Installed package version $VERSION_ID into $SF_USERNAME"
      exit 0
      ;;
    ERROR)
      echo "::error::Package install failed (request Id: $REQUEST_ID)"
      echo "::group::package install error details"
      jq '.' "$REPORT_JSON" 2>/dev/null || cat "$REPORT_JSON"
      echo "::endgroup::"
      exit 1
      ;;
    IN_PROGRESS|"")
      # Keep polling until timeout.
      ;;
    *)
      echo "::error::Unexpected package install status '${INSTALL_STATUS}' (request Id: $REQUEST_ID)"
      echo "::group::package install report details"
      jq '.' "$REPORT_JSON" 2>/dev/null || cat "$REPORT_JSON"
      echo "::endgroup::"
      exit 1
      ;;
  esac
done
