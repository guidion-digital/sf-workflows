#!/usr/bin/env bash
# Post a Block Kit Slack message for native package version create + install.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/log.sh
source "$SCRIPT_DIR/lib/log.sh"

: "${SLACK_TOKEN:?SLACK_TOKEN is required}"
: "${SLACK_CHANNEL:?SLACK_CHANNEL is required}"
: "${WORKFLOW_STATUS:?WORKFLOW_STATUS is required}"

ENVIRONMENT="${ENVIRONMENT:-}"
PACKAGE_NAME="${PACKAGE_NAME:-}"
NEXT_VERSION="${NEXT_VERSION:-}"
PACKAGE_VERSION_FULL="${PACKAGE_VERSION_FULL:-}"
DISPLAY_VERSION="${PACKAGE_VERSION_FULL:-$NEXT_VERSION}"
VERSION_ID="${VERSION_ID:-}"
SF_USERNAME="${SF_USERNAME:-}"
ERROR_SUMMARY="${ERROR_SUMMARY:-}"
INSTALL_REQUEST_ID="${INSTALL_REQUEST_ID:-}"
SF_BASE_URL="${SF_BASE_URL:-}"
GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-}"
GITHUB_REF_NAME="${GITHUB_REF_NAME:-}"
GITHUB_SHA="${GITHUB_SHA:-}"
GITHUB_ACTOR="${GITHUB_ACTOR:-}"
GITHUB_SERVER_URL="${GITHUB_SERVER_URL:-https://github.com}"
GITHUB_RUN_ID="${GITHUB_RUN_ID:-}"
GITHUB_RUN_ATTEMPT="${GITHUB_RUN_ATTEMPT:-1}"

REPO_NAME="${GITHUB_REPOSITORY##*/}"
SHORT_SHA=$(printf '%.7s' "$GITHUB_SHA")
RUN_URL="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"
COMMIT_URL="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/commit/${GITHUB_SHA}"

SF_DEPLOY_URL=""
if [ -n "$INSTALL_REQUEST_ID" ] && [ -n "$SF_BASE_URL" ]; then
  SF_DEPLOY_URL="${SF_BASE_URL}/lightning/setup/DeployStatus/page?address=%2Fchangemgmt%2FmonitorDeploymentsDetails.apexp%3FasyncId%3D${INSTALL_REQUEST_ID}"
fi

case "$WORKFLOW_STATUS" in
  success)
    if [ "${GITHUB_RUN_ATTEMPT}" -gt 1 ] 2>/dev/null; then
      TITLE="✅ *Package Deploy Succeeded* (restarted attempt ${GITHUB_RUN_ATTEMPT}) — \`${ENVIRONMENT}\`"
    else
      TITLE="✅ *Package Deploy Succeeded* — \`${ENVIRONMENT}\`"
    fi
    FALLBACK="Package deploy succeeded in ${ENVIRONMENT}"
    ;;
  cancelled)
    TITLE="🚫 *Package Deploy Canceled* — \`${ENVIRONMENT}\`"
    FALLBACK="Package deploy canceled in ${ENVIRONMENT}"
    ;;
  *)
    TITLE="❌ *Package Deploy Failed* — \`${ENVIRONMENT}\`"
    FALLBACK="Package deploy failed in ${ENVIRONMENT}"
    ;;
esac

field() {
  local label="$1"
  local value="$2"
  if [ -z "$value" ]; then
    echo "null"
    return
  fi
  jq -n --arg label "$label" --arg value "$value" \
    '{type: "mrkdwn", text: ("*" + $label + ":*\n" + $value)}'
}

COMMIT_FIELD_VALUE=""
if [ -n "$SHORT_SHA" ]; then
  COMMIT_FIELD_VALUE="<${COMMIT_URL}|\`${SHORT_SHA}\`>"
fi

VERSION_ID_FIELD_VALUE=""
if [ -n "$VERSION_ID" ]; then
  VERSION_ID_FIELD_VALUE="\`${VERSION_ID}\`"
fi

FIELDS_JSON=$(jq -n \
  --argjson repo "$(field "Repo" "$REPO_NAME")" \
  --argjson branch "$(field "Branch" "$GITHUB_REF_NAME")" \
  --argjson environment "$(field "Environment" "$ENVIRONMENT")" \
  --argjson package "$(field "Package" "$PACKAGE_NAME")" \
  --argjson version "$(field "Version" "$DISPLAY_VERSION")" \
  --argjson version_id "$(field "Version Id" "$VERSION_ID_FIELD_VALUE")" \
  --argjson target_org "$(field "Target org" "$SF_USERNAME")" \
  --argjson started_by "$(field "Started by" "$GITHUB_ACTOR")" \
  --argjson commit "$(field "Commit" "$COMMIT_FIELD_VALUE")" \
  '[
    $repo, $branch, $environment, $package, $version,
    $version_id, $target_org, $started_by, $commit
  ] | map(select(. != null))')

CONTEXT_TEXT="Installed into target org."
if [ "$WORKFLOW_STATUS" = "success" ]; then
  if [ "$ENVIRONMENT" = "prod" ] || [ "$GITHUB_REF_NAME" = "prod" ]; then
    CONTEXT_TEXT="Installed into target org. Package version was promoted and release tagged."
  else
    CONTEXT_TEXT="Installed into target org. Release tagged."
  fi
elif [ "$WORKFLOW_STATUS" != "success" ]; then
  CONTEXT_TEXT="Package deploy did not complete successfully."
fi

EXTRA_BLOCKS='[]'
if [ "$WORKFLOW_STATUS" != "success" ]; then
  if [ -n "$ERROR_SUMMARY" ]; then
    TRUNCATED_ERROR=$(printf '%.1500s' "$ERROR_SUMMARY")
    EXTRA_BLOCKS=$(jq -n --arg error_msg "$TRUNCATED_ERROR" \
      '[
        {type: "section", text: {type: "mrkdwn", text: ("*Error Details:*\n```" + $error_msg + "```")}},
        {type: "divider"},
        {type: "section", text: {type: "mrkdwn", text: "*🔄 To retry:* Click \u0027View Workflow\u0027, then *Re-run all jobs*"}}
      ]')
  else
    EXTRA_BLOCKS=$(jq -n \
      '[{type: "section", text: {type: "mrkdwn", text: "*🔄 To retry:* Click \u0027View Workflow\u0027, then *Re-run all jobs*"}}]')
  fi
fi

SF_BUTTON="null"
if [ -n "$SF_DEPLOY_URL" ]; then
  SF_BUTTON=$(jq -n --arg url "$SF_DEPLOY_URL" \
    '{type: "button", text: {type: "plain_text", text: "🔍 Track in Salesforce"}, url: $url, style: "primary"}')
fi

PAYLOAD=$(jq -n \
  --arg channel "$SLACK_CHANNEL" \
  --arg fallback "$FALLBACK" \
  --arg title "$TITLE" \
  --arg context_text "$CONTEXT_TEXT" \
  --arg run_url "$RUN_URL" \
  --arg commit_url "$COMMIT_URL" \
  --argjson fields "$FIELDS_JSON" \
  --argjson extra "$EXTRA_BLOCKS" \
  --argjson sf_button "$SF_BUTTON" \
  '{
    channel: $channel,
    text: $fallback,
    blocks: (
      [
        {type: "section", text: {type: "mrkdwn", text: $title}},
        {type: "section", fields: $fields},
        {type: "context", elements: [{type: "mrkdwn", text: $context_text}]}
      ]
      + $extra
      + [
        {
          type: "actions",
          elements: (
            [
              {type: "button", text: {type: "plain_text", text: "📋 View Workflow"}, url: $run_url},
              {type: "button", text: {type: "plain_text", text: "🔗 View Commit"}, url: $commit_url}
            ]
            + (if $sf_button != null then [$sf_button] else [] end)
          )
        }
      ]
    )
  }')

RESPONSE=$(curl -s -X POST https://slack.com/api/chat.postMessage \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $SLACK_TOKEN" \
  -d "$PAYLOAD")

if [ "$(printf '%s' "$RESPONSE" | jq -r '.ok')" != "true" ]; then
  echo "::warning::Slack notification failed: $(printf '%s' "$RESPONSE" | jq -r '.error // "unknown"')"
  log_step "Slack notification failed (non-fatal)"
  exit 0
fi

log_success "Slack package deploy notification posted"
