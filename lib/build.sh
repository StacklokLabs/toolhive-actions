#!/usr/bin/env bash
# Shared build and push of skills and AI-tool plugins for the composite
# actions. Called by path, like daemon.sh, with TOOLHIVE_API_URL pointing at a
# running ToolHive API server:
#
#   bash "$GITHUB_ACTION_PATH/../lib/build.sh" build <skill|ai-plugin> <path> [reference...]
#     Builds the directory once per reference, or once with ToolHive's default
#     reference when none is given. Prints each built reference on its own
#     line to stdout; progress goes to stderr.
#
#   bash "$GITHUB_ACTION_PATH/../lib/build.sh" push <skill|ai-plugin> <reference...>
#     Pushes each reference in order and stops at the first failure.
#
#   bash "$GITHUB_ACTION_PATH/../lib/build.sh" require-oidc
#     Fails unless the job can request a GitHub OIDC token. ToolHive signs
#     pushes keylessly with that token and otherwise falls back to an
#     interactive browser sign-in, which cannot work in CI.

set -euo pipefail

# Sets LABEL and CAPITALIZED_LABEL for a ToolHive command group.
set_label() {
  case "$1" in
    skill) LABEL="skill"; CAPITALIZED_LABEL="Skill" ;;
    ai-plugin) LABEL="AI-tool plugin"; CAPITALIZED_LABEL="AI-tool plugin" ;;
    *)
      echo "::error::Unknown kind '$1'; expected 'skill' or 'ai-plugin'."
      exit 2
      ;;
  esac
}

build_one() {
  local kind="$1" path="$2" reference
  shift 2
  echo "Building $LABEL from $path..." >&2
  reference=$(thv "$kind" build "$path" "$@" | tail -n 1)
  if [ -z "$reference" ]; then
    echo "::error::$CAPITALIZED_LABEL build returned an empty reference." >&2
    exit 1
  fi
  echo "Built $LABEL: $reference" >&2
  printf '%s\n' "$reference"
}

build() {
  local kind="${1:-}" path="${2:-}"
  set_label "$kind"
  if [ -z "$path" ]; then
    echo "::error::Usage: build.sh build <skill|ai-plugin> <path> [reference...]"
    exit 2
  fi
  shift 2

  if [ "$#" -eq 0 ]; then
    build_one "$kind" "$path"
    return 0
  fi
  local reference
  for reference in "$@"; do
    build_one "$kind" "$path" --tag "$reference"
  done
}

push() {
  local kind="${1:-}"
  set_label "$kind"
  shift
  local reference
  for reference in "$@"; do
    echo "Pushing $reference..."
    if ! thv "$kind" push "$reference"; then
      echo "::error::Failed to push $reference."
      exit 1
    fi
    echo "Pushed $LABEL: $reference"
  done
}

require_oidc() {
  if [ -z "${ACTIONS_ID_TOKEN_REQUEST_URL:-}" ] || [ -z "${ACTIONS_ID_TOKEN_REQUEST_TOKEN:-}" ]; then
    echo "::error::Pushing signs artifacts with the job's GitHub OIDC token, but this job cannot request one. Add 'permissions: id-token: write' to the job."
    exit 1
  fi
}

case "${1:-}" in
  build) shift; build "$@" ;;
  push) shift; push "$@" ;;
  require-oidc) require_oidc ;;
  *)
    echo "::error::Usage: build.sh build|push|require-oidc"
    exit 2
    ;;
esac
