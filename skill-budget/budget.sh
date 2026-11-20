#!/usr/bin/env bash
# Estimate the context cost of skills and report it, with deltas against a
# base commit. Called by skill-budget/action.yml:
#
#   bash "$GITHUB_ACTION_PATH/budget.sh" measure
#     Reads INPUT_PATHS, INPUT_MAX_SKILL_TOKENS, INPUT_MAX_SKILL_LINES and
#     INPUT_BASE_REF. Outputs: report-file, report-markdown, over-budget,
#     changed.
#
#   bash "$GITHUB_ACTION_PATH/budget.sh" comment
#     Posts or updates the sticky pull request comment. Reads REPORT_FILE,
#     REPORT_MARKDOWN, INPUT_COMMENT_KEY and GH_TOKEN.
#
# Token counts are estimates: ceil(characters / 4). Agents load every
# skill's description in every session, and a skill's SKILL.md when the skill
# is used; the other files of a skill are read on demand.
#
# Runs on the bash 3.2 that ships with macOS: no associative arrays, no
# mapfile.

set -euo pipefail

# shellcheck source=lib/paths.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/paths.sh"

write_output() {
  printf '%s=%s\n' "$1" "$2" >> "${GITHUB_OUTPUT:?GITHUB_OUTPUT is not set}"
}

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

check_positive_integer() {
  if ! [[ "$2" =~ ^[1-9][0-9]*$ ]]; then
    echo "::error::The '$1' input must be a positive integer."
    exit 1
  fi
}

check_comment_key() {
  if ! [[ "${INPUT_COMMENT_KEY:-default}" =~ ^[A-Za-z0-9_.-]+$ ]]; then
    echo "::error::The 'comment-key' input may only contain letters, digits, '.', '_' and '-'."
    exit 1
  fi
}

# Characters in a file, counted as Unicode code points.
file_chars() {
  jq -R -s 'length' < "$1"
}

file_lines() {
  awk 'END { print NR }' "$1"
}

# Characters in the frontmatter description; 0 when there is none.
description_chars() {
  local description
  description=$(yq --front-matter=extract '.description // ""' "$1" 2>/dev/null) || description=""
  printf '%s' "$description" | jq -R -s 'length'
}

# Text files only: binary files are not read into an agent's context.
is_text_file() {
  [ -s "$1" ] && LC_ALL=C grep -Iq '' "$1"
}

# Prints the metrics of a skill directory on disk as JSON.
measure_dir() {
  local dir="$1" file directory_chars=0 chars
  while IFS= read -r -d '' file; do
    if is_text_file "$file"; then
      chars=$(file_chars "$file")
      directory_chars=$((directory_chars + chars))
    fi
  done < <(find "$dir" -type f -print0)
  jq -n -c \
    --argjson skill_md_chars "$(file_chars "$dir/SKILL.md")" \
    --argjson skill_md_lines "$(file_lines "$dir/SKILL.md")" \
    --argjson description_chars "$(description_chars "$dir/SKILL.md")" \
    --argjson directory_chars "$directory_chars" \
    '{skill_md_chars: $skill_md_chars, skill_md_lines: $skill_md_lines,
      description_chars: $description_chars, directory_chars: $directory_chars}'
}

# Prints the metrics of a skill directory at a commit as JSON. Arguments:
# repository, commit, directory path relative to the repository root, scratch
# directory.
measure_commit() {
  local repo="$1" commit="$2" prefix="$3" scratch="$4" file target
  rm -rf "$scratch"
  mkdir -p "$scratch"
  while IFS= read -r -d '' file; do
    target="$scratch/${file#"$prefix"}"
    mkdir -p "$(dirname "$target")"
    git -C "$repo" show "$commit:$file" > "$target"
  done < <(git -C "$repo" ls-tree -r -z --name-only "$commit" -- "$prefix")
  measure_dir "$scratch"
}

measure() {
  check_positive_integer max-skill-tokens "${INPUT_MAX_SKILL_TOKENS:-5000}"
  check_positive_integer max-skill-lines "${INPUT_MAX_SKILL_LINES:-500}"
  local max_tokens="${INPUT_MAX_SKILL_TOKENS:-5000}" max_lines="${INPUT_MAX_SKILL_LINES:-500}"
  local base="${INPUT_BASE_REF:-}"

  local tool
  for tool in jq yq git; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      echo "::error::$tool is required to measure skills."
      exit 1
    fi
  done

  local temp_root work_dir targets results
  temp_root="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
  work_dir=$(mktemp -d "${temp_root}/toolhive-skill-budget.XXXXXX")
  targets="$work_dir/targets.tsv"
  results="$work_dir/results.jsonl"
  : > "$targets"
  : > "$results"

  if ! resolve_paths "${INPUT_PATHS:-}" "$targets" "skill"; then
    exit 1
  fi

  local base_note="none" warned_unavailable=""
  local type path current base_metrics base_status repo prefix
  while IFS=$'\t' read -r type path; do
    current=$(measure_dir "$path")
    base_metrics=null
    base_status=none
    if [ -n "$base" ]; then
      if repo=$(git -C "$path" rev-parse --show-toplevel 2>/dev/null) \
        && prefix=$(git -C "$path" rev-parse --show-prefix); then
        if git -C "$repo" cat-file -e "${base}^{commit}" 2>/dev/null; then
          base_note=available
          if git -C "$repo" cat-file -e "${base}:${prefix}SKILL.md" 2>/dev/null; then
            base_metrics=$(measure_commit "$repo" "$base" "$prefix" "$work_dir/base")
            base_status=found
          else
            base_status=new
          fi
        else
          base_status=unavailable
          if [[ "$warned_unavailable" != *"|$repo|"* ]]; then
            echo "::warning::Base commit $base is not available in $repo, so the report has no deltas. Check out with 'fetch-depth: 0' to compare against the base."
            warned_unavailable="${warned_unavailable}|$repo|"
          fi
        fi
      else
        base_status=unavailable
        echo "::warning::$path is not in a Git repository, so it has no deltas."
      fi
    fi

    jq -n -c \
      --arg path "$path" \
      --argjson current "$current" \
      --argjson base "$base_metrics" \
      --arg base_status "$base_status" \
      --argjson max_tokens "$max_tokens" \
      --argjson max_lines "$max_lines" '
      def tokens: {
        skill_md_tokens: ((.skill_md_chars + 3) / 4 | floor),
        skill_md_lines: .skill_md_lines,
        directory_tokens: ((.directory_chars + 3) / 4 | floor),
        description_tokens: ((.description_chars + 3) / 4 | floor)};
      ($current | tokens) as $now
      | {path: $path, name: ($path | split("/") | last),
         current: $now,
         base: (if $base == null then null else ($base | tokens) end),
         base_status: $base_status,
         breaches: ([
           if $now.skill_md_tokens > $max_tokens then
             "SKILL.md is about \($now.skill_md_tokens) tokens (limit \($max_tokens))" else empty end,
           if $now.skill_md_lines > $max_lines then
             "SKILL.md has \($now.skill_md_lines) lines (limit \($max_lines))" else empty end])}
      ' >> "$results"
  done < "$targets"

  local report="$work_dir/report.json"
  jq -s \
    --argjson max_tokens "$max_tokens" \
    --argjson max_lines "$max_lines" \
    --arg base "$base" \
    --arg base_note "$base_note" '
    def delta($key): if .base_status == "found" then .current[$key] - .base[$key]
      elif .base_status == "new" then .current[$key] else null end;
    map(. + {delta: (if .base_status == "found" or .base_status == "new" then
      {skill_md_tokens: delta("skill_md_tokens"), skill_md_lines: delta("skill_md_lines"),
       directory_tokens: delta("directory_tokens"), description_tokens: delta("description_tokens")}
      else null end)}) as $skills
    | {limits: {max_skill_tokens: $max_tokens, max_skill_lines: $max_lines},
       base: (if $base == "" then null else $base end),
       skills: $skills,
       description_tokens: {
         current: ([$skills[].current.description_tokens] | add // 0),
         delta: (if $base_note == "available" then ([$skills[].delta.description_tokens // 0] | add // 0) else null end)},
       over_budget: any($skills[]; .breaches | length > 0),
       changed: (any($skills[]; .breaches | length > 0)
         or any($skills[]; .delta != null and (.delta | to_entries | any(.value != 0))))}
    ' "$results" > "$report"

  local markdown over_budget changed
  markdown=$(render_markdown "$report")
  over_budget=$(jq -r '.over_budget' "$report")
  changed=$(jq -r '.changed' "$report")

  jq -r '.skills[] | . as $s | .breaches[] | "::warning file=\($s.path)/SKILL.md,title=Skill budget::\(.)"' "$report"
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    printf '%s\n' "$markdown" >> "$GITHUB_STEP_SUMMARY"
  fi

  write_output report-file "$report"
  write_output over-budget "$over_budget"
  write_output changed "$changed"
  write_multiline_output report-markdown "$markdown"
  printf '%s\n' "$markdown"
}

render_markdown() {
  jq -r '
    def signed: if . > 0 then "+\(.)" elif . < 0 then "−\(-.)" else "±0" end;
    def cell($key): .current[$key] as $value
      | if .base_status == "new" then "\($value) (new)"
        elif .delta != null and .delta[$key] != 0 then "\($value) (\(.delta[$key] | signed))"
        else "\($value)" end;
    def escape: gsub("\\|"; "\\|");
    "### Skill budget",
    "",
    "Token counts are estimates (characters ÷ 4). Limits per SKILL.md: \(.limits.max_skill_tokens) tokens and \(.limits.max_skill_lines) lines."
      + (if .base != null and (.skills | any(.base_status == "found" or .base_status == "new"))
         then " Changes are against `\(.base[0:12])`." else "" end),
    "",
    "| Skill | SKILL.md tokens | SKILL.md lines | Directory tokens | Description tokens | Status |",
    "|-------|-----------------|----------------|------------------|--------------------|--------|",
    (.skills[] | "| `\(.path | escape)` | \(cell("skill_md_tokens")) | \(cell("skill_md_lines")) | \(cell("directory_tokens")) | \(cell("description_tokens")) | \(if (.breaches | length) > 0 then "❌ Over budget" else "✅" end) |"),
    "",
    "**All descriptions:** \(.description_tokens.current) tokens"
      + (if .description_tokens.delta != null and .description_tokens.delta != 0
         then " (\(.description_tokens.delta | signed))" else "" end)
      + ". Agents load every skill description in every session.",
    (if .over_budget then
       "",
       (.skills[] | . as $s | .breaches[] | "- ❌ `\($s.path | escape)`: \(.)")
     else empty end)
  ' "$1"
}

comment() {
  check_comment_key
  local report="${REPORT_FILE:?REPORT_FILE is not set}"
  local markdown="${REPORT_MARKDOWN:-}"
  local marker="<!-- toolhive-skill-budget:${INPUT_COMMENT_KEY:-default} -->"

  if [ "${GITHUB_EVENT_NAME:-}" != "pull_request" ]; then
    echo "::notice::Skipping the budget comment: this run was triggered by '${GITHUB_EVENT_NAME:-unknown}', not pull_request."
    return 0
  fi
  local event="${GITHUB_EVENT_PATH:-}" pr head_repo
  pr=$(jq -r '.pull_request.number // empty' "$event" 2>/dev/null || true)
  head_repo=$(jq -r '.pull_request.head.repo.full_name // empty' "$event" 2>/dev/null || true)
  if [ -z "$pr" ]; then
    echo "::notice::Skipping the budget comment: the event has no pull request number."
    return 0
  fi
  if [ "$head_repo" != "${GITHUB_REPOSITORY:-}" ]; then
    echo "::notice::Skipping the budget comment: pull requests from forks get a read-only token."
    return 0
  fi
  if [ -z "${GH_TOKEN:-}" ]; then
    echo "::notice::Skipping the budget comment: no 'github-token' was given."
    return 0
  fi
  if ! command -v gh >/dev/null 2>&1; then
    echo "::error::The GitHub CLI (gh) is required to comment."
    exit 1
  fi

  local repo="$GITHUB_REPOSITORY" existing errors
  errors=$(mktemp)
  if ! existing=$(gh api --paginate "repos/$repo/issues/$pr/comments" \
      --jq ".[] | select(.body | startswith(\"$marker\")) | .id" 2>"$errors"); then
    comment_failed "$errors" "read comments"
    return 0
  fi
  existing="${existing%%$'\n'*}"

  local body
  if [ "$(jq -r '.changed' "$report")" = "true" ]; then
    body="$marker"$'\n'"$markdown"
  elif [ -n "$existing" ]; then
    body="$marker"$'\n'"### Skill budget"$'\n\n'"No budget changes in the latest commit."
  else
    echo "No budget changes; no comment needed."
    return 0
  fi

  if [ -n "$existing" ]; then
    if gh api -X PATCH "repos/$repo/issues/comments/$existing" -f body="$body" >/dev/null 2>"$errors"; then
      echo "Updated budget comment $existing."
    else
      comment_failed "$errors" "update the comment"
    fi
  else
    if gh api -X POST "repos/$repo/issues/$pr/comments" -f body="$body" >/dev/null 2>"$errors"; then
      echo "Posted budget comment."
    else
      comment_failed "$errors" "post the comment"
    fi
  fi
}

# A missing permission is a warning; any other API error fails the step.
comment_failed() {
  local errors="$1" action="$2"
  cat "$errors" >&2
  if grep -q 'HTTP 403' "$errors"; then
    echo "::warning::Could not $action: the token lacks permission. Grant 'pull-requests: write' to the job."
    return 0
  fi
  echo "::error::Could not $action on the pull request."
  exit 1
}

case "${1:-}" in
  measure) measure ;;
  comment) comment ;;
  *)
    echo "::error::Usage: budget.sh measure|comment"
    exit 2
    ;;
esac
