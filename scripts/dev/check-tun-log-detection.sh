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

mkdir -p "$tmp_dir/logs"
LOG_DIR="$tmp_dir/logs"

run_case() {
  local name="$1"
  local adapter_line="$2"
  local traffic_line="$3"
  local expected="$4"
  local result

  printf '%s\n%s\n' "$adapter_line" "$traffic_line" > "$LOG_DIR/mihomo.out.log"

  if tun_log_tun_source_line > "$tmp_dir/out"; then
    result="pass"
  else
    result="fail"
  fi

  if [ "$result" != "$expected" ]; then
    echo "not ok - $name: got $result, expected $expected" >&2
    [ -s "$tmp_dir/out" ] && sed 's/^/  /' "$tmp_dir/out" >&2
    return 1
  fi

  echo "ok - $name"
}

run_case \
  "detects 198.18.0.x tun traffic" \
  "[TUN] Tun adapter listening at: Meta([198.18.0.1/30],[])" \
  "[TCP] 198.18.0.2:43820 --> example.com:443 match RuleSet" \
  "pass"

run_case \
  "detects 198.18.0.x tun traffic without arrow spacing" \
  "[TUN] Tun adapter listening at: Meta([198.18.0.1/30],[])" \
  "[TCP] 198.18.0.2:43820-->example.com:443 match RuleSet" \
  "pass"

run_case \
  "detects 28.0.0.0/8 tun traffic" \
  "[TUN] Tun adapter listening at: Meta([28.0.0.1/30],[])" \
  "[TCP] 28.3.4.5:43820 --> example.com:443 match RuleSet" \
  "pass"

run_case \
  "detects traffic from parsed adapter cidr" \
  "[TUN] Tun adapter listening at: Meta([172.31.9.1/30],[])" \
  "[TCP] 172.31.9.2:43820 --> example.com:443 match RuleSet" \
  "pass"

run_case \
  "ignores unrelated source traffic" \
  "[TUN] Tun adapter listening at: Meta([198.18.0.1/30],[])" \
  "[TCP] 10.0.0.2:43820 --> example.com:443 match RuleSet" \
  "fail"
