#!/usr/bin/env bash
# Check that the code in skills refers to things that exist in the
# repository. Called by skill-refs/action.yml:
#
#   bash "$GITHUB_ACTION_PATH/refs.sh"
#
# Reads INPUT_PATHS, INPUT_REPO_ROOT, INPUT_ALLOWLIST and INPUT_FAIL.
# Outputs: findings, report-file.
#
# Checks, all in code only (inline code spans, shell or untagged fences):
#   path-unresolved   a backticked path that exists neither next to the
#                     Markdown file, in the skill, nor in the repository
#   task-unknown      `task <target>` for a target the Taskfile does not define
#   workflow-unknown  `gh workflow run <workflow>` or .github/workflows/<file>
#                     for a workflow that does not exist
#
# Taskfiles are read with yq and never executed.
#
# Runs on the bash 3.2 that ships with macOS: no associative arrays, no
# mapfile.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
# shellcheck source=lib/paths.sh
source "$SCRIPT_DIR/../lib/paths.sh"

readonly TASKFILE_NAMES="Taskfile.yml taskfile.yml Taskfile.yaml taskfile.yaml Taskfile.dist.yml taskfile.dist.yml Taskfile.dist.yaml taskfile.dist.yaml"

write_output() {
  printf '%s=%s\n' "$1" "$2" >> "${GITHUB_OUTPUT:?GITHUB_OUTPUT is not set}"
}

# Newline-delimited lists; membership via contains_line.
ALLOW_PATHS=""
ALLOW_TASKS=""
ALLOW_WORKFLOWS=""
KNOWN_TASKS=""
UNKNOWN_NAMESPACES=""
KNOWN_WORKFLOWS=""
HAS_TASKFILE=false
UNKNOWN_FLAT=false

contains_line() {
  [[ $'\n'"$2"$'\n' == *$'\n'"$1"$'\n'* ]]
}

# True when the value matches one of the newline-delimited bash patterns.
matches_pattern() {
  local value="$1" patterns="$2" pattern
  while IFS= read -r pattern; do
    [ -z "$pattern" ] && continue
    # shellcheck disable=SC2053 # The pattern is intentionally unquoted.
    if [[ "$value" == $pattern ]]; then
      return 0
    fi
  done <<< "$patterns"
  return 1
}

load_allowlist() {
  local file="$1" line entry
  while IFS= read -r line || [ -n "$line" ]; do
    entry=$(paths_trim "$line")
    case "$entry" in
      ''|'#'*) ;;
      task:*) ALLOW_TASKS="${ALLOW_TASKS}${entry#task:}"$'\n' ;;
      workflow:*) ALLOW_WORKFLOWS="${ALLOW_WORKFLOWS}${entry#workflow:}"$'\n' ;;
      *) ALLOW_PATHS="${ALLOW_PATHS}${entry#./}"$'\n' ;;
    esac
  done < "$file"
}

find_taskfile() {
  local dir="$1" name
  for name in $TASKFILE_NAMES; do
    if [ -f "$dir/$name" ]; then
      printf '%s' "$dir/$name"
      return 0
    fi
  done
  return 1
}

# Prints the task names and aliases a Taskfile defines.
taskfile_tasks() {
  yq '(.tasks // {}) | to_entries | .[] |
      [.key] + ((select(.value | tag == "!!map") | .value.aliases) // []) | .[]' "$1"
}

load_taskfile() {
  local repo_root="$1" taskfile namespace target include_dir included aliases alias task flatten prefix
  taskfile=$(find_taskfile "$repo_root") || return 0
  HAS_TASKFILE=true
  # Task fails on a Taskfile it cannot parse, and so does this check, rather
  # than report every task as undefined.
  if ! KNOWN_TASKS=$(taskfile_tasks "$taskfile"); then
    echo "::error::Could not parse $taskfile."
    exit 1
  fi
  local includes tasks
  if ! includes=$(yq '(.includes // {}) | to_entries | .[] |
      [.key,
       (.value | select(tag == "!!str")) // .value.taskfile // "",
       ((.value | select(tag == "!!map") | .flatten) // false),
       (((.value | select(tag == "!!map") | .aliases) // []) | join(" "))] | @tsv' "$taskfile"); then
    echo "::error::Could not read the includes of $taskfile."
    exit 1
  fi

  # One level of includes: "<namespace>\t<taskfile>\t<flatten>\t<aliases>".
  while IFS=$'\t' read -r namespace target flatten aliases; do
    [ -z "$namespace" ] && continue
    included=""
    if [[ "$target" != *://* && "$target" != *'{{'* && -n "$target" ]]; then
      target="$repo_root/${target#./}"
      if [ -d "$target" ]; then
        include_dir="$target"
        included=$(find_taskfile "$include_dir" || true)
      elif [ -f "$target" ]; then
        included="$target"
      fi
    fi
    if [ -z "$included" ] && [ "$flatten" = "true" ]; then
      # A flattened include that cannot be read may define any task name.
      UNKNOWN_FLAT=true
      continue
    fi
    if [ -z "$included" ]; then
      # Remote, templated or missing: any task in this namespace may exist.
      UNKNOWN_NAMESPACES="${UNKNOWN_NAMESPACES}${namespace}"$'\n'
      for alias in $aliases; do
        UNKNOWN_NAMESPACES="${UNKNOWN_NAMESPACES}${alias}"$'\n'
      done
      continue
    fi
    if ! tasks=$(taskfile_tasks "$included"); then
      echo "::error::Could not parse $included, included as '$namespace' by $taskfile."
      exit 1
    fi
    # As Task resolves them: a flattened include adds its tasks without a
    # namespace, and its namespace is not a valid prefix. Otherwise tasks are
    # <namespace>:<task> (also under namespace aliases), and an included
    # default task also runs as the bare namespace.
    while IFS= read -r task; do
      [ -z "$task" ] && continue
      if [ "$flatten" = "true" ]; then
        KNOWN_TASKS="${KNOWN_TASKS}"$'\n'"${task}"
        continue
      fi
      for prefix in $namespace $aliases; do
        KNOWN_TASKS="${KNOWN_TASKS}"$'\n'"${prefix}:${task}"
        if [ "$task" = "default" ]; then
          KNOWN_TASKS="${KNOWN_TASKS}"$'\n'"${prefix}"
        fi
      done
    done <<< "$tasks"
  done <<< "$includes"
}

load_workflows() {
  local dir="$1/.github/workflows" file name
  [ -d "$dir" ] || return 0
  for file in "$dir"/*.yml "$dir"/*.yaml; do
    [ -f "$file" ] || continue
    KNOWN_WORKFLOWS="${KNOWN_WORKFLOWS}${file##*/}"$'\n'
    name=$(yq '.name // ""' "$file" 2>/dev/null || true)
    if [ -n "$name" ]; then
      KNOWN_WORKFLOWS="${KNOWN_WORKFLOWS}${name}"$'\n'
    fi
  done
}

WORK_DIR=""
FINDINGS_FILE=""
add_finding() {
  # file, line, rule, reference, message
  printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" >> "$FINDINGS_FILE"
}

# Prints the path with ./ segments removed and dir/.. pairs collapsed.
clean_path() {
  local path="$1" part out=""
  local IFS=/
  for part in $path; do
    case "$part" in
      ''|.) ;;
      ..)
        if [ -n "$out" ] && [ "${out##*/}" != ".." ]; then
          if [[ "$out" == */* ]]; then out="${out%/*}"; else out=""; fi
        else
          out="${out:+$out/}.."
        fi
        ;;
      *) out="${out:+$out/}$part" ;;
    esac
  done
  printf '%s' "$out"
}

check_path() {
  local file="$1" line="$2" span="$3" skill="$4" repo_root="$5" skill_from_root="$6"
  local ref="$span" first

  # Not a path: commands, options, URLs, variables, templates and other
  # placeholders, globs, home and absolute paths, anchors.
  case "$ref" in
    *[[:space:]]*|-*|*=*|@*|'#'*|'~'*|/*|*://*|*'<'*|*'>'*|*'$'*|*'{'*|*'}'*|*'*'*|*'?'*|*'['*|*...*|*…*) return 0 ;;
  esac
  # Placeholder tokens such as vX.Y.Z, NNNN-slug or YYYY-MM-DD.
  if [[ "$ref" =~ X\.Y ]] || [[ "$ref" =~ (^|[^A-Za-z])(N{2,}|Y{4}|M{2}|D{2}|X{2,})([^A-Za-z]|$) ]]; then
    return 0
  fi
  ref="${ref%%#*}"
  # Strip a ::symbol suffix, then :line or :line:column.
  ref="${ref%%::*}"
  while [[ "$ref" =~ ^(.*):[0-9]+$ ]]; do
    ref="${BASH_REMATCH[1]}"
  done
  [ -z "$ref" ] && return 0

  # Path-like: explicitly relative, or a slash and a file extension that
  # starts with a letter (not a version such as release/v1.2.3), or a first
  # segment that exists in the skill or the repository.
  first="${ref%%/*}"
  if ! [[ "$ref" == ./* || "$ref" == ../* ]] \
    && ! [[ "$ref" == */* && "${ref##*/}" =~ ^[^.].*\.[A-Za-z][A-Za-z0-9]{0,9}$ ]] \
    && ! [ -e "$skill/$first" ] && ! [ -e "$repo_root/$first" ]; then
    return 0
  fi

  # Resolve next to the Markdown file, in the skill, next to the skill (a
  # sibling skill) or in the repository.
  if [ -e "$(dirname "$file")/$ref" ] || [ -e "$skill/$ref" ] \
    || [ -e "$(dirname "$skill")/$ref" ] || [ -e "$repo_root/$ref" ]; then
    return 0
  fi
  if matches_pattern "$(clean_path "$ref")" "$ALLOW_PATHS" \
    || matches_pattern "$(clean_path "$skill_from_root/$ref")" "$ALLOW_PATHS"; then
    return 0
  fi
  add_finding "$file" "$line" path-unresolved "$span" \
    "\`$span\` does not exist in the skill or the repository."
}

check_task() {
  local file="$1" line="$2"
  shift 2
  [ "$HAS_TASKFILE" = true ] || return 0
  [ "$UNKNOWN_FLAT" = true ] && return 0
  local word skip_next=false target namespace known
  for word in "$@"; do
    if $skip_next; then skip_next=false; continue; fi
    case "$word" in
      --) break ;;
      -d|--dir|-t|--taskfile|--dir=*|--taskfile=*|-d?*|-t?*) return 0 ;;
      -o|--output|-C|--concurrency|-I|--interval|--sort) skip_next=true; continue ;;
      # A redirection target, as in "> out.log".
      '>'|'>>'|'<'|[0-9]'>'|[0-9]'>>') skip_next=true; continue ;;
      -*|*=*|*'$'*|*'{{'*|*'*'*|*'`'*|*'>'*|*'<'*) continue ;;
    esac
    target="$word"
    if contains_line "$target" "$KNOWN_TASKS" || matches_pattern "$target" "$KNOWN_TASKS"; then
      continue
    fi
    known=false
    namespace="$target"
    while [[ "$namespace" == *:* ]]; do
      namespace="${namespace%:*}"
      if contains_line "$namespace" "$UNKNOWN_NAMESPACES"; then known=true; break; fi
    done
    $known && continue
    matches_pattern "$target" "$ALLOW_TASKS" && continue
    add_finding "$file" "$line" task-unknown "task $target" \
      "Task '$target' is not defined in the repository Taskfile."
  done
}

check_workflow_run() {
  local file="$1" line="$2"
  shift 2
  local word skip_next=false workflow=""
  for word in "$@"; do
    case "$word" in
      -R|--repo|--repo=*|-R?*) return 0 ;;
    esac
  done
  for word in "$@"; do
    if $skip_next; then skip_next=false; continue; fi
    case "$word" in
      -r|--ref|-f|--raw-field|-F|--field) skip_next=true; continue ;;
      -*) continue ;;
    esac
    workflow="$word"
    break
  done
  [ -z "$workflow" ] && return 0
  case "$workflow" in
    *'$'*|*'{{'*|*'<'*) return 0 ;;
  esac
  [[ "$workflow" =~ ^[0-9]+$ ]] && return 0
  check_workflow "$file" "$line" "$workflow" "gh workflow run $workflow"
}

check_workflow() {
  local file="$1" line="$2" workflow="$3" reference="$4"
  contains_line "$workflow" "$KNOWN_WORKFLOWS" && return 0
  matches_pattern "$workflow" "$ALLOW_WORKFLOWS" && return 0
  add_finding "$file" "$line" workflow-unknown "$reference" \
    "Workflow '$workflow' does not exist in .github/workflows."
}

scan_skill() {
  local skill="$1" repo_root="$2" skill_from_root="$3"
  local -a files=() words
  local file kind line text list records
  # Lists and records go through files, not process substitution, so a
  # failing find or awk fails the step instead of looking like a clean scan.
  list="$WORK_DIR/files"
  records="$WORK_DIR/records.tsv"
  # -H follows a symlinked skill directory itself.
  if ! find -H "$skill" -type f -name '*.md' -not -path "$skill/assets/*" -print0 | sort -z > "$list"; then
    echo "::error::Could not list the Markdown files of $skill."
    exit 1
  fi
  while IFS= read -r -d '' file; do
    files+=("$file")
  done < "$list"
  [ "${#files[@]}" -eq 0 ] && return 0

  if ! awk -f "$SCRIPT_DIR/extract.awk" "${files[@]}" > "$records"; then
    echo "::error::Could not read the Markdown files of $skill."
    exit 1
  fi
  while IFS=$'\t' read -r kind file line text; do
    case "$kind" in
      P) check_path "$file" "$line" "$text" "$skill" "$repo_root" "$skill_from_root" ;;
      C)
        IFS=$'\037' read -r -a words <<< "$text"
        # Skip leading VAR=value assignments.
        while [ "${#words[@]}" -gt 0 ] && [[ "${words[0]}" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; do
          words=("${words[@]:1}")
        done
        [ "${#words[@]}" -eq 0 ] && continue
        if [ "${words[0]}" = task ]; then
          check_task "$file" "$line" "${words[@]:1}"
        elif [ "${#words[@]}" -ge 3 ] && [ "${words[0]}" = gh ] && [ "${words[1]}" = workflow ] && [ "${words[2]}" = run ]; then
          check_workflow_run "$file" "$line" "${words[@]:3}"
        fi
        ;;
      W) check_workflow "$file" "$line" "${text##*/}" "$text" ;;
    esac
  done < "$records"
}

main() {
  # No fallback for an empty value, which would silently disable failing.
  case "${INPUT_FAIL-false}" in
    true|false) ;;
    *) echo "::error::The 'fail' input must be exactly 'true' or 'false'."; exit 1 ;;
  esac
  local tool
  for tool in jq yq awk; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      echo "::error::$tool is required to check skill references."
      exit 1
    fi
  done

  local repo_root="${INPUT_REPO_ROOT:-.}"
  repo_root="${repo_root%/}"
  [ -z "$repo_root" ] && repo_root="/"
  if [ ! -d "$repo_root" ]; then
    echo "::error::The 'repo-root' directory was not found: $repo_root"
    exit 1
  fi

  local allowlist="${INPUT_ALLOWLIST:-}"
  if [ -n "$allowlist" ]; then
    if [ ! -f "$allowlist" ]; then
      echo "::error::The allowlist file was not found: $allowlist"
      exit 1
    fi
    load_allowlist "$allowlist"
  elif [ -f "$repo_root/.skill-refs-allow" ]; then
    load_allowlist "$repo_root/.skill-refs-allow"
  fi

  local temp_root work_dir targets
  temp_root="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
  work_dir=$(mktemp -d "${temp_root}/toolhive-skill-refs.XXXXXX")
  WORK_DIR="$work_dir"
  targets="$work_dir/targets.tsv"
  FINDINGS_FILE="$work_dir/findings.tsv"
  : > "$targets"
  : > "$FINDINGS_FILE"

  if ! resolve_paths "${INPUT_PATHS:-}" "$targets" "skill"; then
    exit 1
  fi

  load_taskfile "$repo_root"
  load_workflows "$repo_root"

  local root_real type skill skill_real skill_from_root
  root_real=$(cd "$repo_root" && pwd -P)
  while IFS=$'\t' read -r type skill; do
    skill_real=$(cd "$skill" && pwd -P)
    skill_from_root="${skill_real#"$root_real"/}"
    [ "$skill_from_root" = "$skill_real" ] && skill_from_root="$skill"
    scan_skill "$skill" "$repo_root" "$skill_from_root"
  done < "$targets"

  local report="$work_dir/report.json" count
  jq -R -s '
    split("\n") | map(select(length > 0) | split("\t")
      | {file: .[0], line: (.[1] | tonumber), rule: .[2], reference: .[3], message: .[4]})
    | unique_by([.file, .line, .rule, .reference])
    | {findings: .}' "$FINDINGS_FILE" > "$report"
  count=$(jq '.findings | length' "$report")

  jq -r '
    def data: gsub("%"; "%25") | gsub("\r"; "%0D") | gsub("\n"; "%0A");
    def prop: data | gsub(":"; "%3A") | gsub(","; "%2C");
    .findings[] | "::warning file=\(.file | prop),line=\(.line),title=\(.rule | prop)::\(.message | data)"
  ' "$report"

  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    jq -r '
      def cell: gsub("\\|"; "\\|") | gsub("\n"; " ");
      "### Skill references",
      "",
      if (.findings | length) == 0 then "All references in code resolve."
      else
        "| Location | Rule | Message |",
        "|----------|------|---------|",
        (.findings[] | "| \(.file | cell):\(.line) | `\(.rule)` | \(.message | cell) |")
      end
    ' "$report" >> "$GITHUB_STEP_SUMMARY"
  fi

  write_output findings "$count"
  write_output report-file "$report"

  echo "Found $count unresolved references."
  if [ "${INPUT_FAIL:-false}" = "true" ] && [ "$count" -gt 0 ]; then
    echo "::error::$count references in skills do not resolve and 'fail' is 'true'."
    exit 1
  fi
}

main
