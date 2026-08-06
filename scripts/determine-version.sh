#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/log.sh
source "$SCRIPT_DIR/lib/log.sh"

BRANCH="${GITHUB_REF_NAME}"
git fetch --tags --force
LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")
log_notice "Last tag: $LAST_TAG"

if [[ "$BRANCH" == "prod" ]]; then
  RANGE="${LAST_TAG}..HEAD"
  if git log "$RANGE" --pretty=%s%n%b | grep -qE 'BREAKING CHANGE|!:'; then
    BUMP=major
  elif git log "$RANGE" --pretty=%s | grep -qE '^feat(\(.+\))?:'; then
    BUMP=minor
  else
    BUMP=patch
  fi
else
  # Dev/other branches always get a disposable patch bump off the latest release tag
  RANGE="${LAST_TAG}..HEAD"
  BUMP=patch
fi
log_notice "Computed bump: $BUMP"

echo "::group::Commits since $LAST_TAG"
git log "$RANGE" --pretty="  %h %s" || echo "  (no commits found)"
echo "::endgroup::"

TAG_VERSION="${LAST_TAG#v}"
TAG_VERSION="${TAG_VERSION%%[-+]*}"
IFS='.' read -r TAG_MAJOR TAG_MINOR TAG_PATCH TAG_BUILD <<< "$TAG_VERSION"
TAG_MAJOR=${TAG_MAJOR:-0}
TAG_MINOR=${TAG_MINOR:-0}
TAG_PATCH=${TAG_PATCH:-0}
TAG_BUILD=${TAG_BUILD:-0}

for part_name in TAG_MAJOR TAG_MINOR TAG_PATCH; do
  part="${!part_name}"
  if [[ ! "$part" =~ ^[0-9]+$ ]]; then
    echo "::error::Could not parse $part_name from tag '$LAST_TAG' (got '$part')"
    exit 1
  fi
done

if [[ ! "$TAG_BUILD" =~ ^[0-9]+$ ]]; then
  echo "::error::Could not parse TAG_BUILD from tag '$LAST_TAG' (got '$TAG_BUILD')"
  exit 1
fi

TAG_BASELINE="${TAG_MAJOR}.${TAG_MINOR}.${TAG_PATCH}"
log_notice "Parsed tag $LAST_TAG → baseline $TAG_BASELINE (build $TAG_BUILD)"

# The git tags can drift behind the Dev Hub's actual released versions (e.g. after a
# tagging gap), which would otherwise let us compute a next version lower than what
# Salesforce already has released. Use the Dev Hub as an additional floor.
PACKAGE_ALIAS=$(jq -r '.packageDirectories[0].package' sfdx-project.json)
PACKAGE_ID=$(jq -r --arg a "$PACKAGE_ALIAS" '.packageAliases[$a] // empty' sfdx-project.json)

HUB_BASELINE="0.0.0"
if [ -n "$PACKAGE_ID" ] && [ -n "${SF_DEVHUB_ALIAS:-}" ]; then
  HUB_BASELINE=$(sf package version list \
    --packages "$PACKAGE_ID" \
    --target-dev-hub "$SF_DEVHUB_ALIAS" \
    --released \
    --json | jq -r '
      [ .result[] | "\(.MajorVersion).\(.MinorVersion).\(.PatchVersion)" ]
      | if length == 0 then "0.0.0" else
          sort_by(split(".") | map(tonumber)) | last
        end
    ')
fi
echo "Dev Hub baseline (highest released version): $HUB_BASELINE"

if [[ ! "$HUB_BASELINE" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "::error::Dev Hub baseline '$HUB_BASELINE' is not a valid MAJOR.MINOR.PATCH string"
  exit 1
fi

BASELINE=$(jq -n -r --arg tag "$TAG_BASELINE" --arg hub "$HUB_BASELINE" '
  ($tag | split(".") | map(tonumber)) as $t |
  ($hub | split(".") | map(tonumber)) as $h |
  if $h > $t then $hub else $tag end
')
log_notice "Selected baseline (max of tag/Dev Hub): $BASELINE"

IFS='.' read -r MAJOR MINOR PATCH <<< "$BASELINE"

case "$BUMP" in
  major)
    MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0
    ;;
  minor)
    MINOR=$((MINOR + 1)); PATCH=0
    ;;
  patch)
    PATCH=$((PATCH + 1))
    ;;
esac

NEXT_VERSION="${MAJOR}.${MINOR}.${PATCH}"

if [[ ! "$NEXT_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "::error::Computed next version '$NEXT_VERSION' is not a valid MAJOR.MINOR.PATCH string"
  exit 1
fi

log_success "Next version: $NEXT_VERSION"
echo "next_version=$NEXT_VERSION" >> "$GITHUB_OUTPUT"
