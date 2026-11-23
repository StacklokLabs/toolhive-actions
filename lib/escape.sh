# shellcheck shell=bash
# Encoding for text that goes into GitHub Actions workflow commands. Source it:
#
#   source "$GITHUB_ACTION_PATH/../lib/escape.sh"
#   echo "::error file=$(escape_property "$file")::$(escape_data "$message")"
#
# Paths come from the repository, so on a fork pull request their author
# controls them. Unencoded, a line break in a directory name would start a
# second workflow command. The runner decodes these sequences again.
#
# Compatible with the bash 3.2 that ships with macOS.

# Encodes a command's message: '%', CR and LF.
escape_data() {
  local value="$1"
  value="${value//\%/%25}"
  value="${value//$'\r'/%0D}"
  value="${value//$'\n'/%0A}"
  printf '%s' "$value"
}

# Encodes a command property such as file= or title=: the message encoding
# plus ':' and ','.
escape_property() {
  local value
  value=$(escape_data "$1")
  value="${value//:/%3A}"
  value="${value//,/%2C}"
  printf '%s' "$value"
}
