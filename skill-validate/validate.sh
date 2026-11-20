#!/usr/bin/env bash
# Validate skills and AI-tool plugins with thv and report the results to
# GitHub Actions. Called by skill-validate/action.yml:
#
#   bash "$GITHUB_ACTION_PATH/validate.sh" resolve
#     Reads INPUT_PATHS and INPUT_FAIL_ON_WARNINGS, resolves the directories
#     to validate and writes them to a new work directory. Outputs: work-dir.
#
#   bash "$GITHUB_ACTION_PATH/validate.sh" validate
#     WORK_DIR/targets.tsv lists "<skill|plugin>\t<path>" lines; skills-publish
#     writes this file itself to validate the directories it discovered.
#     Reads WORK_DIR, INPUT_FAIL_ON_WARNINGS and TOOLHIVE_API_URL, validates
#     every resolved directory, emits annotations and a step summary, and
#     writes report.json to WORK_DIR. Outputs: valid, report-file,
#     error-count, warning-count.
#
# Runs on the bash 3.2 that ships with macOS: no associative arrays, no
# mapfile.

set -euo pipefail

# First thv release whose validate output includes structured findings.
readonly FINDINGS_VERSION="v0.67.0"
readonly SKILL_MARKER="SKILL.md"
readonly PLUGIN_MARKER=".claude-plugin/plugin.json"

# shellcheck source=lib/paths.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/paths.sh"

write_output() {
  printf '%s=%s\n' "$1" "$2" >> "${GITHUB_OUTPUT:?GITHUB_OUTPUT is not set}"
}

# Prints "<count> <noun>": plural <count> <singular> [<plural>].
plural() {
  if [ "$1" -eq 1 ]; then
    printf '1 %s' "$2"
  else
    printf '%s %s' "$1" "${3:-${2}s}"
  fi
}

check_fail_on_warnings() {
  case "${INPUT_FAIL_ON_WARNINGS:-false}" in
    true|false) ;;
    *)
      echo "::error::The 'fail-on-warnings' input must be exactly 'true' or 'false'."
      exit 1
      ;;
  esac
}

resolve() {
  check_fail_on_warnings

  if ! command -v thv >/dev/null 2>&1; then
    echo "::error::ToolHive CLI (thv) is not installed. Use the install action first."
    exit 1
  fi
  if ! command -v jq >/dev/null 2>&1; then
    echo "::error::jq is required to read thv validation results."
    exit 1
  fi

  local temp_root work_dir targets
  temp_root="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
  work_dir=$(mktemp -d "${temp_root}/toolhive-skill-validate.XXXXXX")
  targets="$work_dir/targets.tsv"
  : > "$targets"

  if ! resolve_paths "${INPUT_PATHS:-}" "$targets" "skill plugin"; then
    exit 1
  fi

  echo "Directories to validate:"
  while IFS=$'\t' read -r type path; do
    echo "  $path ($type)"
  done < "$targets"
  write_output work-dir "$work_dir"
}

# Prints the path GitHub expects in an annotation: relative to the workspace.
annotation_path() {
  local path="$1" workspace="${GITHUB_WORKSPACE:-}"
  if [ -n "$workspace" ] && [[ "$path" == "$workspace"/* ]]; then
    path="${path#"$workspace"/}"
  fi
  printf '%s' "$path"
}

validate() {
  check_fail_on_warnings
  local work_dir="${WORK_DIR:?WORK_DIR is not set}"
  local targets="$work_dir/targets.tsv" results="$work_dir/results.jsonl"
  local report="$work_dir/report.json"
  : > "$results"

  local type path command output stderr_file rc
  stderr_file="$work_dir/stderr"
  while IFS=$'\t' read -r type path; do
    case "$type" in
      skill) command=skill ;;
      plugin) command=ai-plugin ;;
      *) echo "::error::Unknown target type '$type' for $path"; exit 1 ;;
    esac

    echo "::group::thv $command validate $path"
    rc=0
    output=$(thv "$command" validate --format json "$path" 2>"$stderr_file") || rc=$?
    cat "$stderr_file" >&2
    printf '%s\n' "$output"
    echo "::endgroup::"

    # thv exits 1 for an invalid skill but still prints the result; anything
    # else (no API server, unknown command) is not a validation result. Slurp
    # so that empty output is an empty array: jq -e accepts empty input as
    # success in jq 1.6.
    if ! printf '%s' "$output" | jq -e -s \
        'length == 1 and (.[0] | type == "object" and (.valid | type == "boolean"))' \
        >/dev/null 2>&1; then
      echo "::error::thv $command validate failed for $path (exit code $rc) without a validation result."
      exit 1
    fi

    printf '%s' "$output" | jq -c \
      --arg path "$path" \
      --arg type "$type" \
      --arg annotation_path "$(annotation_path "$path")" \
      '{path: $path, type: $type, valid: .valid,
        errors: (.errors // []), warnings: (.warnings // [])}
       + (if .findings then {findings: .findings} else {} end)
       + {annotation_path: $annotation_path}' >> "$results"
  done < "$targets"

  # Every target must have produced exactly one result.
  local expected actual
  expected=$(grep -c '' "$targets" || true)
  actual=$(grep -c '' "$results" || true)
  if [ "$expected" -eq 0 ] || [ "$actual" -ne "$expected" ]; then
    echo "::error::Expected $expected validation results but got $actual."
    exit 1
  fi

  jq -s '{valid: all(.[]; .valid), results: map(del(.annotation_path))}' "$results" > "$report"

  emit_annotations "$results"
  write_summary "$results"

  local valid error_count warning_count invalid_count total legacy_count
  valid=$(jq -r '.valid' "$report")
  error_count=$(jq '[.results[].errors | length] | add // 0' "$report")
  warning_count=$(jq '[.results[].warnings | length] | add // 0' "$report")
  invalid_count=$(jq '[.results[] | select(.valid | not)] | length' "$report")
  total=$(jq '.results | length' "$report")
  legacy_count=$(jq '[.results[] | select(has("findings") | not)
    | select((.errors | length) + (.warnings | length) > 0)] | length' "$report")

  write_output valid "$valid"
  write_output report-file "$report"
  write_output error-count "$error_count"
  write_output warning-count "$warning_count"

  if [ "$legacy_count" -gt 0 ]; then
    echo "::notice::This thv version reports findings without file and line. Install thv $FINDINGS_VERSION or later for line-level annotations and SKILL.md reference checks."
  fi

  echo "Validated $(plural "$total" directory directories): $(plural "$error_count" error), $(plural "$warning_count" warning)."
  if [ "$invalid_count" -gt 0 ]; then
    echo "::error::Validation failed for $invalid_count of $(plural "$total" directory directories)."
    exit 1
  fi
  if [ "${INPUT_FAIL_ON_WARNINGS:-false}" = "true" ] && [ "$warning_count" -gt 0 ]; then
    echo "::error::Validation reported $(plural "$warning_count" warning) and 'fail-on-warnings' is 'true'."
    exit 1
  fi
}

# One annotation per finding. With findings, it points at the reported file
# and line; with only the string lists (older thv), at the manifest file.
emit_annotations() {
  jq -r --arg skill_marker "$SKILL_MARKER" --arg plugin_marker "$PLUGIN_MARKER" '
    def data: gsub("%"; "%25") | gsub("\r"; "%0D") | gsub("\n"; "%0A");
    def prop: data | gsub(":"; "%3A") | gsub(","; "%2C");
    def annotation($level; $file; $line; $title; $message):
      "::\($level) file=\($file | prop)"
      + (if $line > 0 then ",line=\($line)" else "" end)
      + ",title=\($title | prop)::\($message | data)";
    .[] as $r
    | ($r.annotation_path) as $dir
    | if $r.findings then
        $r.findings[]
        | annotation(if .severity == "error" then "error" else "warning" end;
                     "\($dir)/\(.file)"; (.line // 0); .rule; .message)
      else
        (if $r.type == "skill" then $skill_marker else $plugin_marker end) as $marker
        | ($r.errors[] | annotation("error"; "\($dir)/\($marker)"; 0; "thv validate"; .)),
          ($r.warnings[] | annotation("warning"; "\($dir)/\($marker)"; 0; "thv validate"; .))
      end
  ' --slurp "$1"
}

write_summary() {
  [ -n "${GITHUB_STEP_SUMMARY:-}" ] || return 0
  jq -r '
    def cell: tostring | gsub("\\|"; "\\|") | gsub("\n"; " ");
    def status: if (.valid | not) then "❌ Invalid"
      elif (.warnings | length) > 0 then "⚠️ Warnings" else "✅ Valid" end;
    def location: .file + (if (.line // 0) > 0 then ":\(.line)" else "" end);
    "### Skill and AI-tool plugin validation",
    "",
    "| Path | Type | Result | Errors | Warnings |",
    "|------|------|--------|--------|----------|",
    (.[] | "| \(.path | cell) | \(.type) | \(status) | \(.errors | length) | \(.warnings | length) |"),
    (.[] | select((.errors | length) + (.warnings | length) > 0)
      | "",
        "#### \(.path | cell)",
        "",
        (if .findings then
           (.findings[] | "- \(if .severity == "error" then "❌" else "⚠️" end) `\(.rule)` \(location | cell): \(.message | cell)")
         else
           (.errors[] | "- ❌ \(. | cell)"),
           (.warnings[] | "- ⚠️ \(. | cell)")
         end))
  ' --slurp "$1" >> "$GITHUB_STEP_SUMMARY"
}

case "${1:-}" in
  resolve) resolve ;;
  validate) validate ;;
  *)
    echo "::error::Usage: validate.sh resolve|validate"
    exit 2
    ;;
esac
