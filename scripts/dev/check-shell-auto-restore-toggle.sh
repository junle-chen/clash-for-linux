#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

test_project="$tmp_dir/project"
mkdir -p "$test_project/scripts/core" "$test_project/runtime"
cp "$PROJECT_DIR/scripts/core/alias.sh" "$test_project/scripts/core/alias.sh"

cat > "$test_project/runtime/config.yaml" <<'YAML'
mixed-port: 7890
YAML

cat > "$test_project/runtime/shell-proxy.env" <<'EOF'
SHELL_PROXY_PERSIST_ENABLED="true"
SHELL_PROXY_PERSIST_TIME="test"
EOF

run_case() {
  local name="$1"
  local env_file_value="$2"
  local env_override="$3"
  local expected="$4"
  local output

  if [ -n "$env_file_value" ]; then
    printf 'export CLASH_SHELL_AUTO_RESTORE_PROXY="%s"\n' "$env_file_value" > "$test_project/.env"
  else
    rm -f "$test_project/.env"
  fi

  output="$(
    env -i \
      HOME="$tmp_dir/home" \
      PATH="$PATH" \
      CLASH_SHELL_AUTO_RESTORE_PROXY="$env_override" \
      bash --noprofile --norc -c '
        unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY no_proxy NO_PROXY
        source "'"$test_project"'/scripts/core/alias.sh"
        printf "%s\n" "${http_proxy:-}"
      '
  )"

  if [ "$output" != "$expected" ]; then
    echo "not ok - $name: got '$output', expected '$expected'" >&2
    return 1
  fi

  echo "ok - $name"
}

run_case "default auto-restores persisted proxy" "" "" "http://127.0.0.1:7890"
run_case "env file disables auto-restore" "false" "" ""
run_case "environment override enables auto-restore" "false" "true" "http://127.0.0.1:7890"
run_case "environment override disables auto-restore" "true" "false" ""
