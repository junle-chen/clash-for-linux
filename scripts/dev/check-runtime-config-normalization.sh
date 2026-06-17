#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
YQ_VERSION="${YQ_VERSION:-v4.52.4}"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/bin" "$tmp_dir/runtime" "$tmp_dir/config" "$tmp_dir/logs"

install_test_yq() {
  local target="$tmp_dir/bin/yq"
  local system_yq

  if [ -n "${CLASH_TEST_YQ_BIN:-}" ] && [ -x "$CLASH_TEST_YQ_BIN" ]; then
    cp "$CLASH_TEST_YQ_BIN" "$target"
    chmod +x "$target"
    return 0
  fi

  if [ -x "$PROJECT_DIR/runtime/bin/yq" ]; then
    cp "$PROJECT_DIR/runtime/bin/yq" "$target"
    chmod +x "$target"
    return 0
  fi

  system_yq="$(command -v yq 2>/dev/null || true)"
  if [ -n "${system_yq:-}" ] && "$system_yq" --version 2>/dev/null | grep -q 'version v4'; then
    cp "$system_yq" "$target"
    chmod +x "$target"
    return 0
  fi

  local arch file url archive extract_dir
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64) file="yq_linux_amd64.tar.gz" ;;
    aarch64|arm64) file="yq_linux_arm64.tar.gz" ;;
    armv7l|armv7*) file="yq_linux_arm.tar.gz" ;;
    *) echo "not ok - unsupported test architecture for yq: $arch" >&2; return 1 ;;
  esac

  url="https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/${file}"
  archive="$tmp_dir/$file"
  extract_dir="$tmp_dir/yq-extract"
  mkdir -p "$extract_dir"
  curl -fsSL "$url" -o "$archive"
  tar -xzf "$archive" -C "$extract_dir"
  find "$extract_dir" -type f -name 'yq*' -perm -111 -print -quit | xargs -r -I{} cp "{}" "$target"
  [ -x "$target" ] || chmod +x "$target" 2>/dev/null || true
  [ -x "$target" ] || { echo "not ok - failed to install temporary yq" >&2; return 1; }
}

install_test_yq

export PROJECT_DIR
export RUNTIME_DIR="$tmp_dir/runtime"
export BIN_DIR="$tmp_dir/bin"
export LOG_DIR="$tmp_dir/logs"
export CONFIG_DIR="$tmp_dir/config"

# shellcheck source=scripts/core/config.sh
source "$PROJECT_DIR/scripts/core/config.sh"

resolve_runtime_ports() {
  printf 'MIXED_PORT_RESOLVED=7891\n'
  printf 'EXTERNAL_CONTROLLER_RESOLVED=0.0.0.0:9090\n'
  printf 'CLASH_DNS_PORT_RESOLVED=1053\n'
}

ensure_controller_secret() { printf 'test-secret\n'; }
runtime_dashboard_dir() { printf '%s/dashboard\n' "$RUNTIME_DIR"; }
config_allow_lan() { printf 'true\n'; }
tun_enabled() { printf 'false\n'; }
tun_stack() { printf 'mixed\n'; }
tun_auto_route() { printf 'false\n'; }
tun_auto_redirect() { printf 'false\n'; }
tun_strict_route() { printf 'false\n'; }
tun_dns_hijack() { printf 'any:53\n'; }

sample_config="$tmp_dir/runtime-config.yaml"
cat > "$sample_config" <<'YAML'
port: 7890
socks-port: 7891
redir-port: 7892
tproxy-port: 7893
mixed-port: 7890
external-controller: 0.0.0.0:9090
secret: old-secret
allow-lan: false
proxies: []
proxy-groups: []
rules: []
YAML

normalize_runtime_config "$sample_config"

assert_yq() {
  local name="$1"
  local expr="$2"
  local expected="$3"
  local actual

  actual="$("$BIN_DIR/yq" eval "$expr" "$sample_config")"
  if [ "$actual" != "$expected" ]; then
    echo "not ok - $name: got '$actual', expected '$expected'" >&2
    "$BIN_DIR/yq" eval '.' "$sample_config" >&2 || true
    return 1
  fi
  echo "ok - $name"
}

assert_yq "keeps resolved mixed-port" '.["mixed-port"]' "7891"
assert_yq "removes legacy port" 'has("port")' "false"
assert_yq "removes legacy socks-port" 'has("socks-port")' "false"
assert_yq "removes legacy redir-port" 'has("redir-port")' "false"
assert_yq "removes legacy tproxy-port" 'has("tproxy-port")' "false"
assert_yq "keeps controller normalization" '.["external-controller"]' "0.0.0.0:9090"
