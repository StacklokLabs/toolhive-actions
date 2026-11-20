#!/usr/bin/env bash
# Build and optionally push every skill and AI-tool plugin under a root.
# Called by skills-publish/action.yml:
#
#   bash "$GITHUB_ACTION_PATH/publish.sh" discover
#     Checks the inputs, the event and the OIDC permission, and finds the
#     skills under INPUT_ROOT and the plugins under INPUT_PLUGINS_ROOT.
#     Outputs: work-dir, validate-work-dir (targets for skill-validate).
#
#   bash "$GITHUB_ACTION_PATH/publish.sh" publish
#     Builds every directory for every tag, then pushes every reference when
#     INPUT_PUSH is 'true', stopping at the first failed push. Outputs:
#     references, references-json: only references that were pushed and
#     signed, or built when not pushing.
#
# Runs on the bash 3.2 that ships with macOS: no associative arrays, no
# mapfile.

set -euo pipefail

readonly SKILL_MARKER="SKILL.md"
readonly PLUGIN_MARKER=".claude-plugin/plugin.json"
# Events that run trusted code from the repository itself. Pushing signs
# artifacts with the job's identity, so it is refused for anything else, in
# particular pull_request, pull_request_target and workflow_run.
readonly TRUSTED_EVENTS="push release workflow_dispatch schedule"

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
readonly LIB_DIR

write_output() {
  printf '%s=%s\n' "$1" "$2" >> "${GITHUB_OUTPUT:?GITHUB_OUTPUT is not set}"
}

# Writes a multiline output with a delimiter that does not occur in the value.
write_multiline_output() {
  local name="$1" value="$2" delimiter
  delimiter="ghadelimiter_${RANDOM}_${RANDOM}_$$"
  while printf '%s\n' "$value" | grep -Fqx -- "$delimiter"; do
    delimiter="${delimiter}_"
  done
  {
    printf '%s<<%s\n' "$name" "$delimiter"
    printf '%s\n' "$value"
    printf '%s\n' "$delimiter"
  } >> "${GITHUB_OUTPUT:?GITHUB_OUTPUT is not set}"
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

check_boolean() {
  case "$2" in
    true|false) ;;
    *)
      echo "::error::The '$1' input must be exactly 'true' or 'false'."
      exit 1
      ;;
  esac
}

# Checks a registry prefix such as ghcr.io/org/repo/skills.
check_prefix() {
  local name="$1" prefix="$2" last
  if [ -z "$prefix" ]; then
    echo "::error::The '$name' input is required."
    exit 1
  fi
  if [[ "$prefix" =~ [[:space:]] ]]; then
    echo "::error::The '$name' input must not contain whitespace."
    exit 1
  fi
  if [[ "$prefix" =~ [[:upper:]] ]]; then
    echo "::error::The '$name' input must be lowercase: $prefix. GitHub owner and repository names can contain capitals, but OCI repository paths cannot."
    exit 1
  fi
  if [[ "$prefix" == */ ]]; then
    echo "::error::The '$name' input must not end with '/': $prefix"
    exit 1
  fi
  if [[ "$prefix" != */* ]]; then
    echo "::error::The '$name' input must include a registry and a repository path, for example ghcr.io/org/skills: $prefix"
    exit 1
  fi
  last="${prefix##*/}"
  if [[ "$prefix" == *@* ]]; then
    echo "::error::The '$name' input must not include a digest: $prefix"
    exit 1
  fi
  if [[ "$last" == *:* ]]; then
    echo "::error::The '$name' input must not include a tag; use the 'tags' input: $prefix"
    exit 1
  fi
}

# Prints the trimmed, nonblank tags, rejecting malformed and duplicate ones.
parse_tags() {
  local line tag seen=$'\n'
  while IFS= read -r line || [ -n "$line" ]; do
    tag=$(trim "$line")
    [ -z "$tag" ] && continue
    if ! [[ "$tag" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$ ]]; then
      echo "::error::Invalid tag '$tag'. Use a plain OCI tag such as v1.2.0 or latest, not a full reference." >&2
      exit 1
    fi
    if [[ "$seen" == *$'\n'"$tag"$'\n'* ]]; then
      echo "::error::The 'tags' input contains the duplicate tag '$tag'." >&2
      exit 1
    fi
    seen="${seen}${tag}"$'\n'
    printf '%s\n' "$tag"
  done <<< "${INPUT_TAGS:-}"
}

# Appends "<type>\t<name>\t<path>\t<prefix>" for each marked subdirectory of a
# root to the targets file.
discover_root() {
  local input="$1" root="$2" type="$3" marker="$4" prefix="$5" targets="$6"
  local dir name found=0

  root="${root%/}"
  if [ ! -d "$root" ]; then
    echo "::error::The '$input' directory was not found: $root"
    exit 1
  fi

  for dir in "$root"/*/; do
    [ -d "$dir" ] || continue
    dir="${dir%/}"
    name="${dir##*/}"
    if [ -f "$dir/$SKILL_MARKER" ] && [ -f "$dir/$PLUGIN_MARKER" ]; then
      echo "::error::$dir has both $SKILL_MARKER and $PLUGIN_MARKER; a directory must be either a skill or an AI-tool plugin."
      exit 1
    fi
    if [ ! -f "$dir/$marker" ]; then
      echo "::warning::Skipping $dir: no $marker."
      continue
    fi
    if [[ "$dir" =~ [[:space:]] ]]; then
      echo "::error::Directory names must not contain whitespace: $dir"
      exit 1
    fi
    printf '%s\t%s\t%s\t%s\n' "$type" "$name" "$dir" "$prefix" >> "$targets"
    found=$((found + 1))
  done

  if [ "$found" -eq 0 ]; then
    echo "::error::No $type directories with $marker found under $root."
    exit 1
  fi
}

discover() {
  # No fallback for empty values: the action's step conditions compare the
  # raw inputs, so an empty validate would skip validation while a default
  # here would claim it runs.
  check_boolean push "${INPUT_PUSH:-}"
  check_boolean validate "${INPUT_VALIDATE:-}"

  local prefix="${INPUT_REGISTRY_PREFIX:-}"
  local plugins_prefix="${INPUT_PLUGINS_REGISTRY_PREFIX:-}"
  check_prefix registry-prefix "$prefix"
  if [ -n "$plugins_prefix" ]; then
    check_prefix plugins-registry-prefix "$plugins_prefix"
  else
    plugins_prefix="$prefix"
  fi

  local tags
  tags=$(parse_tags)
  if [ -z "$tags" ]; then
    echo "::error::The 'tags' input is required, for example 'v1.2.0' and 'latest' on separate lines."
    exit 1
  fi

  if [ "${INPUT_PUSH:-false}" = "true" ]; then
    local event="${GITHUB_EVENT_NAME:-}"
    if [[ " $TRUSTED_EVENTS " != *" $event "* ]]; then
      echo "::error::Pushing is only allowed on these events: ${TRUSTED_EVENTS// /, }. This run was triggered by '${event:-unknown}'. Use push: 'false' for a build-only check."
      exit 1
    fi
    bash "$LIB_DIR/build.sh" require-oidc
  fi

  if ! command -v thv >/dev/null 2>&1; then
    echo "::error::ToolHive CLI (thv) is not installed. Use the install action first."
    exit 1
  fi
  if ! command -v jq >/dev/null 2>&1; then
    echo "::error::jq is required to write the references-json output."
    exit 1
  fi

  local temp_root work_dir targets
  temp_root="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
  work_dir=$(mktemp -d "${temp_root}/toolhive-skills-publish.XXXXXX")
  targets="$work_dir/targets.tsv"
  : > "$targets"
  printf '%s\n' "$tags" > "$work_dir/tags"

  discover_root root "${INPUT_ROOT:-skills}" skill "$SKILL_MARKER" "$prefix" "$targets"
  if [ -n "${INPUT_PLUGINS_ROOT:-}" ]; then
    discover_root plugins-root "$INPUT_PLUGINS_ROOT" plugin "$PLUGIN_MARKER" "$plugins_prefix" "$targets"
  fi

  # Two directories with the same name under the same prefix would publish to
  # the same repository and overwrite each other.
  local collisions
  collisions=$(awk -F'\t' '{ key = $4 "/" $2; if (key in seen) print key; seen[key] = 1 }' "$targets")
  if [ -n "$collisions" ]; then
    while IFS= read -r collision; do
      echo "::error::More than one directory would publish to $collision. Rename one, or set 'plugins-registry-prefix' to separate skills and plugins."
    done <<< "$collisions"
    exit 1
  fi

  echo "Directories to publish:"
  local type name path target_prefix
  while IFS=$'\t' read -r type name path target_prefix; do
    echo "  $path ($type) -> $target_prefix/$name"
  done < "$targets"

  # Validation reads the discovered directories as they are, not as the
  # patterns skill-validate accepts, so names with glob characters stay
  # literal.
  mkdir -p "$work_dir/validate"
  cut -f1,3 "$targets" > "$work_dir/validate/targets.tsv"

  write_output work-dir "$work_dir"
  write_output validate-work-dir "$work_dir/validate"
}

publish() {
  local work_dir="${WORK_DIR:?WORK_DIR is not set}"
  local targets="$work_dir/targets.tsv"
  local built="$work_dir/built.tsv" published="$work_dir/published.tsv"
  : > "$built"
  : > "$published"

  local -a tags=()
  local tag
  while IFS= read -r tag; do
    tags+=("$tag")
  done < "$work_dir/tags"

  # Build everything first, so nothing is pushed when any build fails.
  local type name path prefix kind output reference
  local -a references
  while IFS=$'\t' read -r type name path prefix; do
    kind=skill
    [ "$type" = plugin ] && kind=ai-plugin
    references=()
    for tag in "${tags[@]}"; do
      references+=("$prefix/$name:$tag")
    done
    output=$(bash "$LIB_DIR/build.sh" build "$kind" "$path" "${references[@]}")
    while IFS= read -r reference; do
      printf '%s\t%s\t%s\n' "$kind" "$name" "$reference" >> "$built"
    done <<< "$output"
  done < "$targets"

  local failed=""
  if [ "${INPUT_PUSH:-false}" = "true" ]; then
    while IFS=$'\t' read -r kind name reference; do
      if ! bash "$LIB_DIR/build.sh" push "$kind" "$reference"; then
        failed="$reference"
        break
      fi
      printf '%s\t%s\t%s\n' "$kind" "$name" "$reference" >> "$published"
    done < "$built"
  else
    cp "$built" "$published"
  fi

  write_multiline_output references "$(cut -f3 "$published")"
  write_output references-json "$(jq -R -s -c '
    split("\n") | map(select(length > 0) | split("\t"))
    | reduce .[] as $row ({}; .[$row[1]] += [$row[2]])' "$published")"
  write_summary "$built" "$published" "$failed"

  if [ -n "$failed" ]; then
    # ToolHive uploads a reference before signing it, so a push that failed
    # while signing can leave the tag in the registry without a signature.
    echo "::error::Stopped at the first failed push ($failed). That tag may already be in the registry without a signature: rerun the job to push and sign it again, or delete the tag. The outputs list only references that were pushed and signed."
    exit 1
  fi
}

write_summary() {
  [ -n "${GITHUB_STEP_SUMMARY:-}" ] || return 0
  local built="$1" published="$2" failed="$3" status
  if [ "${INPUT_PUSH:-false}" = "true" ]; then
    status="Pushed and signed"
  else
    status="Built (not pushed)"
  fi
  {
    echo
    echo "### Published skills and AI-tool plugins"
    echo
    echo "| Name | Type | Reference | Status |"
    echo "|------|------|-----------|--------|"
    local kind name reference row_status
    while IFS=$'\t' read -r kind name reference; do
      if grep -Fqx -- "$(printf '%s\t%s\t%s' "$kind" "$name" "$reference")" "$published"; then
        row_status="✅ $status"
      elif [ "$reference" = "$failed" ]; then
        row_status="❌ Push failed; the tag may be in the registry unsigned"
      else
        row_status="⏭️ Not pushed"
      fi
      echo "| $name | ${kind#ai-} | \`$reference\` | $row_status |"
    done < "$built"
  } >> "$GITHUB_STEP_SUMMARY"
}

case "${1:-}" in
  discover) discover ;;
  publish) publish ;;
  *)
    echo "::error::Usage: publish.sh discover|publish"
    exit 2
    ;;
esac
