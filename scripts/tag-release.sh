#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/log.sh
source "$SCRIPT_DIR/lib/log.sh"

TAG="v${NEXT_VERSION}"
git tag "$TAG"
git push origin "$TAG"
log_success "Tagged and pushed $TAG"
