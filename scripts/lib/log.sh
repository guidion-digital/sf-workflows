#!/usr/bin/env bash
# Shared log helpers for GitHub Actions workflow scripts.
# GH Actions renders ANSI colors in job logs (same mechanism SF CLI uses for
# bold-green "Successfully authorized ..." lines).

# Bold green — success / final outcomes
log_success() {
  printf '\033[1;32m%s\033[0m\n' "$*"
}

# Bold cyan — notable intermediate status (baselines, version picks, etc.)
log_notice() {
  printf '\033[1;36m%s\033[0m\n' "$*"
}

# Bold default — step banners / section intros
log_step() {
  printf '\033[1m%s\033[0m\n' "$*"
}
