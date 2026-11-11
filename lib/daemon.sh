#!/usr/bin/env bash
# Shared ToolHive API server (thv serve) lifecycle for the composite actions.
#
# Every thv skill / ai-plugin command goes through the API server. Actions call
# this script by path, because a composite action cannot reference another
# action of this repository by local path (./ resolves to the caller's
# workspace):
#
#   bash "$GITHUB_ACTION_PATH/../lib/daemon.sh" start
#   bash "$GITHUB_ACTION_PATH/../lib/daemon.sh" stop
#
# start
#   Reuses the server at TOOLHIVE_API_URL (default http://127.0.0.1:8080) when
#   it is ready. Otherwise starts `thv serve` on a free loopback port and waits
#   for it to become ready. Writes to GITHUB_OUTPUT:
#     url      API URL to export as TOOLHIVE_API_URL for later steps
#     pid      PID of the started server (empty when reused)
#     started  'true' when this invocation started the server
#
# stop
#   Reads DAEMON_PID and DAEMON_STARTED from the environment and stops the
#   server only when DAEMON_STARTED is 'true'.
#
# Readiness: /health answering 204 or 503. Skills and AI-tool plugins do not
# need a container runtime, so 503 (runtime unavailable) still means ready.

set -euo pipefail

readonly DEFAULT_URL="http://127.0.0.1:8080"
readonly MAX_WAIT_SECONDS=30
readonly STOP_WAIT_SECONDS=10

health_code() {
  curl -s --max-time 2 -o /dev/null -w '%{http_code}' "$1/health" 2>/dev/null || true
}

is_ready() {
  case "$(health_code "$1")" in
    204|503) return 0 ;;
    *) return 1 ;;
  esac
}

# True while the process exists and has not exited. A stopped server whose
# parent shell is gone can linger as a zombie until init reaps it, and
# `kill -0` still succeeds on zombies, so check the process state too.
is_alive() {
  kill -0 "$1" 2>/dev/null || return 1
  case "$(ps -o stat= -p "$1" 2>/dev/null)" in
    ""|Z*) return 1 ;;
    *) return 0 ;;
  esac
}

write_output() {
  printf '%s=%s\n' "$1" "$2" >> "${GITHUB_OUTPUT:?GITHUB_OUTPUT is not set}"
}

free_port() {
  python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()' 2>/dev/null || {
    echo "::warning::python3 not available for port selection, falling back to 8080" >&2
    echo 8080
  }
}

start_daemon() {
  if ! command -v thv >/dev/null 2>&1; then
    echo "::error::ToolHive CLI (thv) is not installed. Use the install action first."
    exit 1
  fi

  if ! command -v curl >/dev/null 2>&1; then
    echo "::error::curl is required to check the ToolHive daemon."
    exit 1
  fi

  local existing_url="${TOOLHIVE_API_URL:-$DEFAULT_URL}"
  if [[ "$existing_url" == *$'\n'* || "$existing_url" == *$'\r'* ]]; then
    echo "::error::TOOLHIVE_API_URL must not contain line breaks."
    exit 1
  fi

  if is_ready "$existing_url"; then
    echo "ToolHive daemon already running at $existing_url"
    write_output url "$existing_url"
    write_output pid ""
    write_output started false
    return 0
  fi

  local port daemon_url daemon_pid
  port=$(free_port)
  daemon_url="http://127.0.0.1:${port}"

  echo "Starting thv serve on port $port..."
  thv serve --host 127.0.0.1 --port "$port" &
  daemon_pid=$!

  # Record ownership before waiting so an always() stop step can clean up
  # even when readiness fails.
  write_output url "$daemon_url"
  write_output pid "$daemon_pid"
  write_output started true

  local elapsed=0
  while [ "$elapsed" -lt "$MAX_WAIT_SECONDS" ]; do
    if ! is_alive "$daemon_pid"; then
      echo "::error::ToolHive daemon process exited unexpectedly."
      wait "$daemon_pid" 2>/dev/null || true
      exit 1
    fi
    if is_ready "$daemon_url"; then
      echo "ToolHive daemon is ready at $daemon_url"
      return 0
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done

  echo "::error::ToolHive daemon failed to start within ${MAX_WAIT_SECONDS} seconds."
  kill "$daemon_pid" 2>/dev/null || true
  exit 1
}

stop_daemon() {
  local daemon_pid="${DAEMON_PID:-}"
  local daemon_started="${DAEMON_STARTED:-false}"

  if [ "$daemon_started" != "true" ]; then
    echo "ToolHive daemon was not started by this action; leaving it running."
    return 0
  fi

  if ! [[ "$daemon_pid" =~ ^[0-9]+$ ]]; then
    echo "::warning::No valid ToolHive daemon PID to stop."
    return 0
  fi

  if ! is_alive "$daemon_pid"; then
    echo "ToolHive daemon (pid $daemon_pid) has already exited."
    return 0
  fi
  kill "$daemon_pid" 2>/dev/null || true

  # The server is not a child of this shell, so `wait` cannot be used; poll
  # until it exits so later steps never observe a half-stopped daemon.
  local elapsed=0
  while is_alive "$daemon_pid"; do
    if [ "$elapsed" -ge "$STOP_WAIT_SECONDS" ]; then
      echo "::warning::ToolHive daemon did not exit after SIGTERM; sending SIGKILL."
      kill -9 "$daemon_pid" 2>/dev/null || true
      break
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  echo "Stopped ToolHive daemon (pid $daemon_pid)."
}

case "${1:-}" in
  start) start_daemon ;;
  stop) stop_daemon ;;
  *)
    echo "::error::Usage: daemon.sh start|stop"
    exit 2
    ;;
esac
