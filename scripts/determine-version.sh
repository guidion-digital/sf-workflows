#!/usr/bin/env bash
set -euo pipefail

BRANCH="${GITHUB_REF_NAME}"
git fetch --tags --force
LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")
echo "Last tag: $LAST_TAG"

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
  BUMP=patch
fi
echo "Computed bump: $BUMP"

VERSION="${LAST_TAG#v}"
IFS='.' read -r MAJOR MINOR PATCH <<< "$VERSION"
MAJOR=${MAJOR:-0}
MINOR=${MINOR:-0}
PATCH=${PATCH:-0}

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
echo "Next version: $NEXT_VERSION"
echo "next_version=$NEXT_VERSION" >> "$GITHUB_OUTPUT"
