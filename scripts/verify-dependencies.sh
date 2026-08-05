#!/usr/bin/env bash
#
# Pre-flight dependency verification for the native `deploy_package_native.yaml` workflow.
#
# Reads the declared dependencies straight from the checked-out repo's sfdx-project.json
# (packageDirectories[0].dependencies), resolves each alias via packageAliases, and checks
# that the target org (SF_USERNAME) has an adequate version of each installed, using the
# DevHub (SF_DEVHUB_ALIAS) to look up package/version identities.
#
# This mirrors the logic in semantic-release-salesforce's src/lib/dependencies.ts
# (verifyAvailabilityOfDependencies) and src/lib/packages.ts (getInstalledPackages), but
# simplified to plain `sf data query` + `jq`, run pre-version-create instead of post.
#
# Required env vars:
#   SF_DEVHUB_ALIAS            - alias/username of the authenticated DevHub org
#   SF_USERNAME                - alias/username of the authenticated target org
#   IS_PRODUCTION               - "true"/"false" - controls exact-match vs semver-floor strictness
#   AUTO_INSTALL_DEPENDENCIES   - "true"/"false" - on failure, attempt install/upgrade + re-check
#
# Exit codes: 0 on success (including "nothing declared"), 1 on unresolved problems.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/log.sh
source "$SCRIPT_DIR/lib/log.sh"

: "${SF_DEVHUB_ALIAS:?SF_DEVHUB_ALIAS is required}"
: "${SF_USERNAME:?SF_USERNAME is required}"
IS_PRODUCTION="${IS_PRODUCTION:-false}"
AUTO_INSTALL_DEPENDENCIES="${AUTO_INSTALL_DEPENDENCIES:-false}"

PROJECT_FILE="sfdx-project.json"

if [ ! -f "$PROJECT_FILE" ]; then
  echo "::error::$PROJECT_FILE not found in $(pwd)"
  exit 1
fi

# --- Step 1: read declared dependency aliases -------------------------------------------

DEP_ALIASES=$(jq -r '.packageDirectories[0].dependencies[]? | .package // empty' "$PROJECT_FILE")

if [ -z "$DEP_ALIASES" ]; then
  log_success "No dependencies declared for this package"
  exit 0
fi

log_notice "Declared dependencies: $(echo "$DEP_ALIASES" | tr '\n' ' ')"

# --- Step 2: resolve each alias via packageAliases, split into pinned (04t) / unpinned (0Ho) ---

DECLARED_JSON="[]"

while IFS= read -r ALIAS; do
  [ -z "$ALIAS" ] && continue

  RESOLVED_ID=$(jq -r --arg a "$ALIAS" '.packageAliases[$a] // empty' "$PROJECT_FILE")
  if [ -z "$RESOLVED_ID" ]; then
    echo "::error::Dependency alias '$ALIAS' is not present in packageAliases"
    exit 1
  fi

  if [[ "$RESOLVED_ID" == 04t* ]]; then
    KIND="pinned"
  elif [[ "$RESOLVED_ID" == 0Ho* ]]; then
    KIND="unpinned"
  else
    echo "::error::Dependency alias '$ALIAS' resolves to unrecognized id '$RESOLVED_ID' (expected a 04t... version id or a 0Ho... package id)"
    exit 1
  fi

  # Unpinned deps may declare a floor like "1.2.0.LATEST" - extract the leading Major.Minor.Patch.
  VERSION_NUMBER=$(jq -r --arg a "$ALIAS" '(.packageDirectories[0].dependencies[]? | select(.package == $a) | .versionNumber) // empty' "$PROJECT_FILE")
  FLOOR=""
  if [ -n "$VERSION_NUMBER" ] && [[ "$VERSION_NUMBER" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+) ]]; then
    FLOOR="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.${BASH_REMATCH[3]}"
  fi

  ENTRY=$(jq -n --arg alias "$ALIAS" --arg id "$RESOLVED_ID" --arg kind "$KIND" --arg floor "$FLOOR" \
    '{alias: $alias, id: $id, kind: $kind, floor: ($floor | select(length > 0))}')
  DECLARED_JSON=$(echo "$DECLARED_JSON" | jq --argjson e "$ENTRY" '. + [$e]')
done <<< "$DEP_ALIASES"

# --- Step 3: look up identity/version info on the DevHub for each distinct resolved id ---

PINNED_IDS=$(echo "$DECLARED_JSON" | jq -r '[.[] | select(.kind=="pinned") | .id] | unique | .[]')
UNPINNED_IDS=$(echo "$DECLARED_JSON" | jq -r '[.[] | select(.kind=="unpinned") | .id] | unique | .[]')

to_soql_id_list() {
  # Reads newline-separated ids from stdin, emits a quoted comma-separated SOQL literal list.
  sed "s/^/'/;s/$/'/" | paste -sd, -
}

PINNED_VERSIONS_JSON="[]"
if [ -n "$PINNED_IDS" ]; then
  ID_LIST=$(echo "$PINNED_IDS" | to_soql_id_list)
  PINNED_VERSIONS_JSON=$(sf data query \
    --query "SELECT Id, SubscriberPackageId, Name, MajorVersion, MinorVersion, PatchVersion FROM SubscriberPackageVersion WHERE Id IN ($ID_LIST)" \
    --use-tooling-api \
    --target-org "$SF_DEVHUB_ALIAS" \
    --json | jq '.result.records')

  while IFS= read -r ID; do
    [ -z "$ID" ] && continue
    FOUND=$(echo "$PINNED_VERSIONS_JSON" | jq --arg id "$ID" '[.[] | select(.Id == $id)] | length')
    if [ "$FOUND" -eq 0 ]; then
      echo "::error::Could not resolve pinned dependency version '$ID' on the DevHub (SubscriberPackageVersion query returned no match)"
      exit 1
    fi
  done <<< "$PINNED_IDS"
fi

UNPINNED_PACKAGES_JSON="[]"
if [ -n "$UNPINNED_IDS" ]; then
  ID_LIST=$(echo "$UNPINNED_IDS" | to_soql_id_list)
  UNPINNED_PACKAGES_JSON=$(sf data query \
    --query "SELECT Id, SubscriberPackageId FROM Package2 WHERE Id IN ($ID_LIST)" \
    --use-tooling-api \
    --target-org "$SF_DEVHUB_ALIAS" \
    --json | jq '.result.records')

  while IFS= read -r ID; do
    [ -z "$ID" ] && continue
    FOUND=$(echo "$UNPINNED_PACKAGES_JSON" | jq --arg id "$ID" '[.[] | select(.Id == $id)] | length')
    if [ "$FOUND" -eq 0 ]; then
      echo "::error::Could not resolve unpinned dependency package '$ID' on the DevHub (Package2 query returned no match)"
      exit 1
    fi
  done <<< "$UNPINNED_IDS"
fi

# --- Step 4: build the normalized "expected" list (one entry per declared dependency) ---

EXPECTED_JSON=$(jq -n \
  --argjson declared "$DECLARED_JSON" \
  --argjson pinned "$PINNED_VERSIONS_JSON" \
  --argjson unpinned "$UNPINNED_PACKAGES_JSON" \
  '
  [ $declared[] | . as $d |
    if $d.kind == "pinned" then
      (($pinned[] | select(.Id == $d.id)) ) as $p |
      {
        alias: $d.alias,
        displayName: $p.Name,
        subscriberPackageId: $p.SubscriberPackageId,
        pinned: true,
        expectedVersionId: $d.id,
        expectedVersion: "\($p.MajorVersion).\($p.MinorVersion).\($p.PatchVersion)",
        floor: null
      }
    else
      (($unpinned[] | select(.Id == $d.id)) ) as $u |
      {
        alias: $d.alias,
        displayName: $d.alias,
        subscriberPackageId: $u.SubscriberPackageId,
        pinned: false,
        expectedVersionId: null,
        expectedVersion: $d.floor,
        floor: $d.floor
      }
    end
  ]
  ')

# --- Step 5: query installed packages in the target org and cross-reference ---

query_installed_packages() {
  sf data query \
    --query "SELECT SubscriberPackageId, SubscriberPackageVersionId, SubscriberPackage.Name, SubscriberPackageVersion.MajorVersion, SubscriberPackageVersion.MinorVersion, SubscriberPackageVersion.PatchVersion FROM InstalledSubscriberPackage" \
    --target-org "$SF_USERNAME" \
    --json | jq '[.result.records[] | {
      subscriberPackageId: .SubscriberPackageId,
      subscriberPackageVersionId: .SubscriberPackageVersionId,
      name: .SubscriberPackage.Name,
      version: "\(.SubscriberPackageVersion.MajorVersion).\(.SubscriberPackageVersion.MinorVersion).\(.SubscriberPackageVersion.PatchVersion)"
    }]'
}

compute_problems() {
  local expected="$1"
  local installed="$2"
  jq -n \
    --argjson expected "$expected" \
    --argjson installed "$installed" \
    --arg isProd "$IS_PRODUCTION" \
    '
    ($isProd == "true") as $prod |
    [ $expected[] | . as $dep |
      ( [ $installed[] | select(.subscriberPackageId == $dep.subscriberPackageId) ] | first ) as $inst |
      if ($inst == null) then
        $dep + { problem: "missing from target org", installedVersion: null, installedVersionId: null }
      elif ($dep.pinned and $prod) then
        if $inst.subscriberPackageVersionId != $dep.expectedVersionId then
          $dep + {
            problem: "mismatch, expected exact \($dep.expectedVersion) (\($dep.expectedVersionId)), found \($inst.version) (\($inst.subscriberPackageVersionId))",
            installedVersion: $inst.version,
            installedVersionId: $inst.subscriberPackageVersionId
          }
        else
          empty
        end
      elif ($dep.expectedVersion == null) then
        # Unpinned dependency with no version floor declared - presence is enough.
        empty
      else
        ($dep.expectedVersion | split(".") | map(tonumber) | (.[0]*1000000 + .[1]*1000 + .[2])) as $expNum |
        ($inst.version | split(".") | map(tonumber) | (.[0]*1000000 + .[1]*1000 + .[2])) as $insNum |
        if $insNum >= $expNum then
          empty
        else
          $dep + {
            problem: "outdated, need >= \($dep.expectedVersion), found \($inst.version)",
            installedVersion: $inst.version,
            installedVersionId: $inst.subscriberPackageVersionId
          }
        end
      end
    ]
    '
}

print_problems() {
  echo "$1" | jq -r '.[] | "  - \(.displayName // .alias) (\(.subscriberPackageId)): \(.problem)"'
}

INSTALLED_JSON=$(query_installed_packages)
PROBLEMS_JSON=$(compute_problems "$EXPECTED_JSON" "$INSTALLED_JSON")
PROBLEM_COUNT=$(echo "$PROBLEMS_JSON" | jq 'length')

if [ "$PROBLEM_COUNT" -eq 0 ]; then
  log_success "All declared dependencies are satisfied in the target organization"
  exit 0
fi

echo "::warning::Found $PROBLEM_COUNT dependency problem(s) in the target organization:"
print_problems "$PROBLEMS_JSON"

if [ "$AUTO_INSTALL_DEPENDENCIES" != "true" ]; then
  echo "::error::Dependency verification failed and AUTO_INSTALL_DEPENDENCIES is not enabled"
  exit 1
fi

# --- Step 6: auto-install remediation (opt-in) ---

log_step "AUTO_INSTALL_DEPENDENCIES is enabled, attempting to install/upgrade problem dependencies..."

echo "$PROBLEMS_JSON" | jq -c '.[]' | while IFS= read -r PROBLEM; do
  ALIAS=$(echo "$PROBLEM" | jq -r '.alias')
  PINNED=$(echo "$PROBLEM" | jq -r '.pinned')

  if [ "$PINNED" == "true" ]; then
    VERSION_ID=$(echo "$PROBLEM" | jq -r '.expectedVersionId')
    echo "Installing pinned dependency '$ALIAS' at $VERSION_ID"
    sf package install --package "$VERSION_ID" --target-org "$SF_USERNAME" --wait 30 --no-prompt \
      || echo "::warning::Install of '$ALIAS' ($VERSION_ID) failed, will be re-checked below"
  else
    PACKAGE_ID=$(echo "$DECLARED_JSON" | jq -r --arg a "$ALIAS" '.[] | select(.alias == $a) | .id')
    FLOOR=$(echo "$PROBLEM" | jq -r '.floor // empty')
    echo "Resolving latest released version of unpinned dependency '$ALIAS' ($PACKAGE_ID) satisfying floor ${FLOOR:-<none>}"

    LATEST_VERSION_ID=$(sf package version list \
      --packages "$PACKAGE_ID" \
      --target-dev-hub "$SF_DEVHUB_ALIAS" \
      --released \
      --json | jq -r --arg floor "$FLOOR" '
        [ .result[]
          | select(($floor == "") or (
              (.MajorVersion*1000000 + .MinorVersion*1000 + .PatchVersion)
              >= ($floor | split(".") | map(tonumber) | (.[0]*1000000 + .[1]*1000 + .[2]))
            ))
        ]
        | sort_by(.MajorVersion, .MinorVersion, .PatchVersion)
        | last
        | (.SubscriberPackageVersionId // empty)
      ')

    if [ -z "$LATEST_VERSION_ID" ]; then
      echo "::warning::Could not find a released version of '$ALIAS' ($PACKAGE_ID) satisfying floor ${FLOOR:-<none>}, skipping install attempt"
      continue
    fi

    echo "Installing unpinned dependency '$ALIAS' at resolved version $LATEST_VERSION_ID"
    sf package install --package "$LATEST_VERSION_ID" --target-org "$SF_USERNAME" --wait 30 --no-prompt \
      || echo "::warning::Install of '$ALIAS' ($LATEST_VERSION_ID) failed, will be re-checked below"
  fi
done

log_step "Re-checking dependency status after install attempts..."
INSTALLED_JSON=$(query_installed_packages)
PROBLEMS_JSON=$(compute_problems "$EXPECTED_JSON" "$INSTALLED_JSON")
PROBLEM_COUNT=$(echo "$PROBLEMS_JSON" | jq 'length')

if [ "$PROBLEM_COUNT" -eq 0 ]; then
  log_success "All declared dependencies are satisfied in the target organization after auto-install remediation"
  exit 0
fi

echo "::error::$PROBLEM_COUNT dependency problem(s) remain in the target organization after auto-install remediation:"
print_problems "$PROBLEMS_JSON"
exit 1
