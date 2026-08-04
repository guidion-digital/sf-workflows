#!/usr/bin/env bash
set -euo pipefail

TAG="v${NEXT_VERSION}"
git tag "$TAG"
git push origin "$TAG"
