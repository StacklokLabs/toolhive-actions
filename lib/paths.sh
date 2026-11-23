# shellcheck shell=bash
# Shared resolution of the 'paths' input of the skill actions. Source it:
#
#   source "$GITHUB_ACTION_PATH/../lib/paths.sh"
#   resolve_paths "$INPUT_PATHS" "$targets_file" "skill plugin" [unmatched_file]
#
# Each nonblank, trimmed line of the input is a directory or a single-level
# glob pattern:
#   - A plain path must be a directory of an accepted type.
#   - A glob skips matches of other types but must match at least one.
#   - '**' is rejected; a directory with both markers is an error.
#   - Entries resolving to the same directory are listed once.
# Appends "<type>\t<path>" lines to the targets file, where type is 'skill'
# (has SKILL.md) or 'plugin' (has .claude-plugin/plugin.json). Prints an
# ::error:: for every problem and returns 1 after checking all entries.
#
# Compatible with the bash 3.2 that ships with macOS.

# shellcheck source=lib/escape.sh
source "$(dirname "${BASH_SOURCE[0]}")/escape.sh"

readonly PATHS_SKILL_MARKER="SKILL.md"
readonly PATHS_PLUGIN_MARKER=".claude-plugin/plugin.json"

paths_trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

# Strips a leading ./ and trailing slashes so equal paths print the same way.
paths_normalize() {
  local path="$1"
  while [[ "$path" == ./* && "$path" != "./" ]]; do
    path="${path#./}"
  done
  while [[ "$path" == */ && "$path" != "/" ]]; do
    path="${path%/}"
  done
  printf '%s' "$path"
}

# Prints "skill", "plugin", "both" or "none" for a directory.
paths_classify() {
  local has_skill=false has_plugin=false
  [ -f "$1/$PATHS_SKILL_MARKER" ] && has_skill=true
  [ -f "$1/$PATHS_PLUGIN_MARKER" ] && has_plugin=true
  if $has_skill && $has_plugin; then
    echo both
  elif $has_skill; then
    echo skill
  elif $has_plugin; then
    echo plugin
  else
    echo none
  fi
}

# Arguments: paths input, targets file, accepted types ("skill plugin" or
# "skill"), and optionally a file that collects glob patterns matching nothing
# instead of failing on them.
resolve_paths() {
  local input="$1" targets="$2" accepted="$3" unmatched="${4:-}"
  local noun="skill or AI-tool plugin" markers="$PATHS_SKILL_MARKER or $PATHS_PLUGIN_MARKER"
  # Validating a plugin covers its bundled skills, under the plugin's rules.
  local levels="'skills/*' and 'plugins/*'; a plugin's bundled skills are validated with the plugin"
  if [ "$accepted" = "skill" ]; then
    noun="skill"
    markers="$PATHS_SKILL_MARKER"
    levels="'skills/*' and 'plugins/*/skills/*'"
  fi

  local seen=$'\n' line entry path type real matched match failed=false count=0
  local -a matches
  local old_ifs
  while IFS= read -r line || [ -n "$line" ]; do
    entry=$(paths_trim "$line")
    [ -z "$entry" ] && continue
    count=$((count + 1))

    if [[ "$entry" == *'**'* ]]; then
      echo "::error::The 'paths' input does not support '**' ($(escape_data "$entry")). List each level instead, for example $levels."
      failed=true
      continue
    fi

    matches=()
    if [[ "$entry" != *[*?[]* ]]; then
      path=$(paths_normalize "$entry")
      if [ ! -d "$path" ]; then
        echo "::error::Directory not found: $(escape_data "$entry")"
        failed=true
        continue
      fi
      matches=("$path")
    else
      # Expand the glob without word splitting.
      old_ifs="$IFS"
      shopt -s nullglob
      IFS=
      # shellcheck disable=SC2206 # Intentional glob expansion of the pattern.
      matches=($entry)
      IFS="$old_ifs"
      shopt -u nullglob
    fi

    matched=0
    for match in ${matches[@]+"${matches[@]}"}; do
      [ -d "$match" ] || continue
      if [[ "$match" == *$'\n'* || "$match" == *$'\r'* || "$match" == *$'\t'* ]]; then
        echo "::error::Matched path contains a line break or tab, which is not supported: $(escape_data "$match")"
        failed=true
        continue
      fi
      path=$(paths_normalize "$match")
      type=$(paths_classify "$path")
      if [ "$type" = both ]; then
        echo "::error::$(escape_data "$path") has both $PATHS_SKILL_MARKER and $PATHS_PLUGIN_MARKER; a directory must be either a skill or an AI-tool plugin."
        failed=true
        matched=$((matched + 1))
        continue
      fi
      if [[ " $accepted " != *" $type "* ]]; then
        # Globs skip other entries; a plain path must be accepted.
        if [[ "$entry" != *[*?[]* ]]; then
          echo "::error::$(escape_data "$entry") is not a $noun directory (no $markers)."
          failed=true
        fi
        continue
      fi
      matched=$((matched + 1))
      real=$(cd -- "$path" && pwd -P)
      if [[ "$seen" == *$'\n'"$real"$'\n'* ]]; then
        continue
      fi
      seen="${seen}${real}"$'\n'
      printf '%s\t%s\n' "$type" "$path" >> "$targets"
    done
    if [ "$matched" -eq 0 ] && [[ "$entry" == *[*?[]* ]]; then
      if [ -n "$unmatched" ]; then
        printf '%s\n' "$entry" >> "$unmatched"
      else
        echo "::error::The pattern '$(escape_data "$entry")' matched no $noun directories."
        failed=true
      fi
    fi
  done <<< "$input"

  if [ "$count" -eq 0 ]; then
    echo "::error::The 'paths' input is required. List $noun directories, one per line."
    return 1
  fi
  if $failed; then
    return 1
  fi
}
