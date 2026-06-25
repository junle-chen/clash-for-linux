#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source_clashctl_for_tests() {
  set -- ""
  # Source the real functions; suppress the no-arg usage printed by the command dispatcher.
  source "$PROJECT_DIR/scripts/core/clashctl.sh" >/dev/null
}

source_clashctl_for_tests

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

prepare() { :; }
ui_warn() { printf 'warn: %s\n' "$*" >> "$tmp_dir/output"; }
ui_next() { printf 'next: %s\n' "$*" >> "$tmp_dir/output"; }
ui_blank() { :; }
system_proxy_env_file() { printf '%s\n' "$tmp_dir/environment"; }
write_runtime_value() { :; }
die_state() {
  printf 'die: %s\nnext: %s\n' "$1" "$2" >> "$tmp_dir/output"
  exit 1
}

run_case() {
  local name="$1"
  local proxy_rc="$2"
  local stop_calls_file="$tmp_dir/stop-calls"
  local output_file="$tmp_dir/output"

  : > "$stop_calls_file"
  : > "$output_file"

  system_proxy_disable() { return "$proxy_rc"; }
  service_stop() { printf 'stop\n' >> "$stop_calls_file"; }
  status_is_running() {
    [ ! -s "$stop_calls_file" ]
  }

  cmd_off > "$output_file"

  if [ "$(wc -l < "$stop_calls_file" | tr -d ' ')" != "1" ]; then
    echo "not ok - $name: service_stop was not called exactly once" >&2
    return 1
  fi

  if ! grep -Fq "代理已关闭" "$output_file"; then
    echo "not ok - $name: success feedback missing" >&2
    sed 's/^/  /' "$output_file" >&2
    return 1
  fi

  echo "ok - $name"
}

run_case "stops runtime after disabling system proxy" 0
run_case "still stops runtime when system proxy cleanup is unsupported" 2

run_stop_failure_case() {
  local stop_calls_file="$tmp_dir/stop-failure-calls"
  local output_file="$tmp_dir/output"

  : > "$stop_calls_file"
  : > "$output_file"

  system_proxy_disable() { return 0; }
  service_stop() {
    printf 'stop\n' >> "$stop_calls_file"
    return 7
  }
  status_is_running() { return 0; }

  if ( cmd_off ) > "$output_file"; then
    echo "not ok - stop failure: cmd_off unexpectedly succeeded" >&2
    return 1
  fi

  if ! grep -Fq "运行后端 stop 返回 7" "$output_file"; then
    echo "not ok - stop failure: missing stop failure detail" >&2
    sed 's/^/  /' "$output_file" >&2
    return 1
  fi

  if grep -Fq "代理已关闭" "$output_file"; then
    echo "not ok - stop failure: printed success after stop failure" >&2
    sed 's/^/  /' "$output_file" >&2
    return 1
  fi

  echo "ok - stop failure returns non-zero"
}

run_persistent_cleanup_blocked_case() {
  local stop_calls_file="$tmp_dir/persistent-cleanup-blocked-calls"
  local output_file="$tmp_dir/output"

  : > "$stop_calls_file"
  : > "$output_file"

  system_proxy_status() { printf 'on\n'; }
  system_proxy_disable() { return 2; }
  service_stop() { printf 'stop\n' >> "$stop_calls_file"; }
  status_is_running() {
    [ ! -s "$stop_calls_file" ]
  }

  if ( cmd_off ) > "$output_file"; then
    echo "not ok - persistent cleanup blocked: cmd_off unexpectedly succeeded" >&2
    return 1
  fi

  if [ "$(wc -l < "$stop_calls_file" | tr -d ' ')" != "1" ]; then
    echo "not ok - persistent cleanup blocked: service_stop was not called exactly once" >&2
    return 1
  fi

  if ! grep -Fq "系统代理持久块未清理" "$output_file"; then
    echo "not ok - persistent cleanup blocked: missing cleanup failure detail" >&2
    sed 's/^/  /' "$output_file" >&2
    return 1
  fi

  if grep -Fq "代理已关闭" "$output_file"; then
    echo "not ok - persistent cleanup blocked: printed success while persistent proxy remained" >&2
    sed 's/^/  /' "$output_file" >&2
    return 1
  fi

  echo "ok - persistent cleanup failure returns non-zero after stopping runtime"
}

run_still_running_case() {
  local stop_calls_file="$tmp_dir/still-running-calls"
  local output_file="$tmp_dir/output"

  : > "$stop_calls_file"
  : > "$output_file"

  system_proxy_disable() { return 0; }
  service_stop() { printf 'stop\n' >> "$stop_calls_file"; }
  status_is_running() { return 0; }
  wait_runtime_stopped() { return 1; }

  if ( cmd_off ) > "$output_file"; then
    echo "not ok - still running: cmd_off unexpectedly succeeded" >&2
    return 1
  fi

  if ! grep -Fq "代理内核仍在运行" "$output_file"; then
    echo "not ok - still running: missing still-running detail" >&2
    sed 's/^/  /' "$output_file" >&2
    return 1
  fi

  if grep -Fq "代理已关闭" "$output_file"; then
    echo "not ok - still running: printed success while runtime stayed up" >&2
    sed 's/^/  /' "$output_file" >&2
    return 1
  fi

  echo "ok - still running returns non-zero"
}

run_stop_failure_case
run_persistent_cleanup_blocked_case
run_still_running_case
