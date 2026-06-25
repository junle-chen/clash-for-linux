#!/usr/bin/env bash

# shellcheck source=scripts/core/common.sh
source "${PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/scripts/core/common.sh"
# shellcheck source=scripts/core/config.sh
source "${PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/scripts/core/config.sh"

GEO_ASSET_DOWNLOADS=(
  "resources/geo/Country.mmdb https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/country.mmdb"
  "resources/geo/geoip.metadb https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.metadb"
  "resources/geo/GeoLite2-ASN.mmdb https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/GeoLite2-ASN.mmdb"
  "resources/geo/GeoIP.dat https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.dat"
  "resources/geo/GeoSite.dat https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geosite.dat"
)

resolve_geo_assets() {
  case "${CLASH_PREDOWNLOAD_GEO:-false}" in
    0|false|no|off|disable|disabled|FALSE|NO|OFF) return 0 ;;
  esac

  [ -n "${PROJECT_DIR:-}" ] || return 0

  local item path url file target

  for item in "${GEO_ASSET_DOWNLOADS[@]}"; do
    path="${item%% *}"
    url="${item#* }"
    file="$(basename "$path")"
    target="$RUNTIME_DIR/$file"

    if ! copy_bundled_asset "geo" "latest" "$file" "$target" "$file"; then
      download_file "$url" "$target" "$file"
    fi
  done
}

resolve_yq() {
  local arch version file url tmp_dir tmp_file

  arch="$(get_arch)"
  version="${YQ_VERSION:-$DEFAULT_YQ_VERSION}"

  if [ -x "$(yq_bin)" ]; then
    return 0
  fi

  case "$arch" in
    amd64) file="yq_linux_amd64.tar.gz" ;;
    arm64) file="yq_linux_arm64.tar.gz" ;;
    armv7) file="yq_linux_arm.tar.gz" ;;
    *) die "暂不支持的 yq 架构：$arch" ;;
  esac

  url="https://github.com/mikefarah/yq/releases/download/${version}/${file}"
  tmp_dir="$(mktemp -d)"
  tmp_file="$tmp_dir/$file"

  if ! copy_bundled_asset "yq" "$version" "$file" "$tmp_file" "yq"; then
    download_file "$url" "$tmp_file" "yq"
  fi
  tar -xzf "$tmp_file" -C "$tmp_dir"

  if [ -f "$tmp_dir/yq_linux_${arch}" ]; then
    install -m 0755 "$tmp_dir/yq_linux_${arch}" "$(yq_bin)"
  elif [ -f "$tmp_dir/yq_linux_arm" ]; then
    install -m 0755 "$tmp_dir/yq_linux_arm" "$(yq_bin)"
  elif [ -f "$tmp_dir/yq" ]; then
    install -m 0755 "$tmp_dir/yq" "$(yq_bin)"
  else
    rm -rf "$tmp_dir"
    die "解压后未找到 yq 可执行文件"
  fi

  rm -rf "$tmp_dir"
}

resolve_mihomo() {
  local arch version file url tmp_file url_base custom_url

  arch="$(get_arch)"
  version="${MIHOMO_VERSION:-$DEFAULT_MIHOMO_VERSION}"
  url_base="${MIHOMO_DOWNLOAD_BASE:-https://github.com/MetaCubeX/mihomo/releases/download}"
  custom_url="${MIHOMO_DOWNLOAD_URL:-}"

  if [ -x "$(mihomo_bin)" ]; then
    return 0
  fi

  case "$arch" in
    amd64) file="mihomo-linux-amd64-compatible-${version}.gz" ;;
    arm64) file="mihomo-linux-arm64-${version}.gz" ;;
    armv7) file="mihomo-linux-armv7-${version}.gz" ;;
    *) die "暂不支持的 Mihomo 架构：$arch" ;;
  esac

  if [ -n "${custom_url:-}" ]; then
    url="$custom_url"
  else
    url="${url_base%/}/${version}/${file}"
  fi
  tmp_file="$(mktemp)"

  if ! copy_bundled_asset "mihomo" "$version" "$file" "$tmp_file" "mihomo"; then
    download_file "$url" "$tmp_file" "mihomo（可在 .env 中设置 MIHOMO_DOWNLOAD_BASE / MIHOMO_DOWNLOAD_URL）"
  fi
  gzip -dc "$tmp_file" > "$(mihomo_bin)"
  chmod +x "$(mihomo_bin)"
  rm -f "$tmp_file"
}

resolve_clash() {
  local arch version version_no_v url_base tmp_file url downloaded="false"
  local candidates file

  arch="$(get_arch)"
  version="${CLASH_VERSION:-$DEFAULT_CLASH_VERSION}"
  version_no_v="${version#v}"
  url_base="${CLASH_DOWNLOAD_BASE:-https://github.com/WindSpiritSR/clash/releases/download}"

  if [ -x "$(clash_bin)" ] \
    && [ "$(read_runtime_value "KERNEL_TYPE_INSTALLED" 2>/dev/null || true)" = "clash" ] \
    && [ "$(read_runtime_value "CLASH_VERSION_INSTALLED" 2>/dev/null || true)" = "$version" ]; then
    return 0
  fi

  case "$arch" in
    amd64)
      candidates="
clash-linux-amd64-${version}.gz
clash-linux-amd64-v${version_no_v}.gz
"
      ;;
    arm64)
      candidates="
clash-linux-arm64-${version}.gz
clash-linux-arm64-v${version_no_v}.gz
clash-linux-armv8-${version}.gz
clash-linux-armv8-v${version_no_v}.gz
"
      ;;
    armv7)
      candidates="
clash-linux-armv7-${version}.gz
clash-linux-armv7-v${version_no_v}.gz
"
      ;;
    *)
      die "暂不支持的 Clash 架构：$arch"
      ;;
  esac

  tmp_file="$(mktemp)"
  rm -f "$tmp_file"

  for file in $candidates; do
    url="${url_base}/${version}/${file}"

    if download_file "$url" "$tmp_file" "clash"; then
      downloaded="true"
      break
    fi
  done

  [ "$downloaded" = "true" ] || {
    rm -f "$tmp_file"
    die "Clash 内核下载失败，请检查版本或在 .env 中覆盖 CLASH_DOWNLOAD_BASE / CLASH_VERSION"
  }

  gzip -dc "$tmp_file" > "$(clash_bin)"
  chmod +x "$(clash_bin)"
  rm -f "$tmp_file"

  write_runtime_value "KERNEL_TYPE_INSTALLED" "clash"
  write_runtime_value "CLASH_VERSION_INSTALLED" "$version"
}

resolve_runtime_kernel() {
  case "$(runtime_kernel_type)" in
    mihomo)
      resolve_mihomo
      write_runtime_value "KERNEL_TYPE_INSTALLED" "mihomo"
      write_runtime_value "MIHOMO_VERSION_INSTALLED" "${MIHOMO_VERSION:-$DEFAULT_MIHOMO_VERSION}"
      ;;
    clash)
      resolve_clash
      ;;
    *)
      die "未知内核类型：$(runtime_kernel_type)"
      ;;
  esac
}

subconverter_version_file_value() {
  read_runtime_value "SUBCONVERTER_VERSION_INSTALLED" 2>/dev/null || true
}

mark_subconverter_version_installed() {
  local version="$1"
  write_runtime_value "SUBCONVERTER_VERSION_INSTALLED" "$version"
}

detect_subconverter_package_type() {
  local file="$1"
  local desc magic

  if tar -tzf "$file" >/dev/null 2>&1; then
    echo "tar.gz"
    return 0
  fi

  magic="$(od -An -tx1 -N4 "$file" 2>/dev/null | tr -d '[:space:]' || true)"

  case "$magic" in
    504b0304|504b0506|504b0708)
      echo "zip"
      return 0
      ;;
    7f454c46)
      echo "binary"
      return 0
      ;;
  esac

  if command -v unzip >/dev/null 2>&1 && unzip -tq "$file" >/dev/null 2>&1; then
    echo "zip"
    return 0
  fi

  desc="$(file -b "$file" 2>/dev/null || true)"
  case "$desc" in
    *ELF*|*executable*)
      echo "binary"
      return 0
      ;;
  esac

  echo "unknown"
}

find_subconverter_binary() {
  local search_dir="$1"
  local found

  found="$(find "$search_dir" \( -type f -o -type l \) -name subconverter -print 2>/dev/null | head -n 1)"
  [ -n "${found:-}" ] || return 1
  echo "$found"
}

subconverter_runtime_layout_ready() {
  local target_dir="$1"

  [ -d "$target_dir" ] || return 1
  [ -d "$target_dir/templates" ] \
    || [ -d "$target_dir/base" ] \
    || [ -d "$target_dir/config" ] \
    || [ -d "$target_dir/rules" ]
}

resolve_subconverter() {
  local arch version file url tmp_dir tmp_file target_dir installed_version
  local extract_dir package_type found_bin target_bin source_dir

  arch="$(get_arch)"
  version="${SUBCONVERTER_VERSION:-$DEFAULT_SUBCONVERTER_VERSION}"
  target_dir="$(subconverter_home)"
  target_bin="$(subconverter_bin)"
  installed_version="$(subconverter_version_file_value)"

  if [ -f "$target_bin" ] && [ "$installed_version" = "$version" ]; then
    chmod +x "$target_bin" 2>/dev/null || true
    if [ -x "$target_bin" ] && subconverter_runtime_layout_ready "$target_dir"; then
      return 0
    fi
  fi

  case "$arch" in
    amd64) file="subconverter_linux64.tar.gz" ;;
    arm64) file="subconverter_aarch64.tar.gz" ;;
    armv7) file="subconverter_armv7.tar.gz" ;;
    *) die "暂不支持的 subconverter 架构：$arch" ;;
  esac

  url="https://github.com/asdlokj1qpi233/subconverter/releases/download/${version}/${file}"
  tmp_dir="$(mktemp -d)"
  tmp_file="$tmp_dir/$file"
  extract_dir="$tmp_dir/extract"

  if ! copy_bundled_asset "subconverter" "$version" "$file" "$tmp_file" "subconverter"; then
    download_file "$url" "$tmp_file" "subconverter"
  fi

  package_type="$(detect_subconverter_package_type "$tmp_file")"

  rm -rf "$target_dir"
  mkdir -p "$target_dir" "$extract_dir"

  case "$package_type" in
    tar.gz)
      tar -xzf "$tmp_file" -C "$extract_dir"
      found_bin="$(find_subconverter_binary "$extract_dir" 2>/dev/null || true)"
      ;;
    zip)
      command -v unzip >/dev/null 2>&1 || die "解压 subconverter zip 失败：系统缺少 unzip"
      unzip -oq "$tmp_file" -d "$extract_dir"
      found_bin="$(find_subconverter_binary "$extract_dir" 2>/dev/null || true)"
      ;;
    binary)
      found_bin="$tmp_file"
      ;;
    *)
      if command -v file >/dev/null 2>&1; then
        file "$tmp_file" >&2 || true
      fi
      die "subconverter 下载内容异常：无法识别下载包类型（文件：$tmp_file）"
      ;;
  esac

  [ -n "${found_bin:-}" ] && [ -f "$found_bin" ] || {
    find "$extract_dir" -maxdepth 3 \( -type f -o -type l \) 2>/dev/null | sed 's/^/  /' >&2 || true
    die "解压后未找到 subconverter 文件"
  }

  if [ "$package_type" = "binary" ]; then
    cp -f "$found_bin" "$target_bin"
  else
    source_dir="$(dirname "$found_bin")"
    cp -a "$source_dir"/. "$target_dir"/
  fi
  chmod +x "$target_bin"

  [ -x "$target_bin" ] || {
    rm -rf "$tmp_dir"
    die "subconverter 文件不可执行：$target_bin"
  }

  mark_subconverter_version_installed "$version"
  rm -rf "$tmp_dir"
}

ensure_runtime_config_ready() {
  local config_file last_file now reason

  config_file="$RUNTIME_DIR/config.yaml"
  last_file="$RUNTIME_DIR/config.last.yaml"

  if [ -s "$config_file" ] && test_runtime_config "$config_file" >/dev/null 2>&1; then
    write_runtime_event_value "RUNTIME_LAST_FALLBACK_USED" "false"
    write_runtime_event_value "RUNTIME_LAST_FALLBACK_TIME" ""
    write_runtime_event_value "RUNTIME_LAST_FALLBACK_REASON" ""
    write_runtime_event_value "RUNTIME_LAST_RISK_LEVEL" "$(calculate_runtime_risk_level)"
    mark_runtime_config_source "runtime"
    return 0
  fi

  reason="当前运行配置不可用"
  warn "当前运行配置不可用，尝试回退到上一次成功配置"

  [ -s "$last_file" ] || die "当前配置不可用，且不存在可回退的最后成功配置：$last_file"

  if test_runtime_config "$last_file" >/dev/null 2>&1; then
    cp -f "$last_file" "$config_file"
    now="$(now_datetime)"
    write_runtime_event_value "RUNTIME_LAST_FALLBACK_USED" "true"
    write_runtime_event_value "RUNTIME_LAST_FALLBACK_TIME" "$now"
    write_runtime_event_value "RUNTIME_LAST_FALLBACK_REASON" "$reason"
    write_runtime_event_value "RUNTIME_LAST_RISK_LEVEL" "$(calculate_runtime_risk_level)"
    mark_runtime_config_source "last_good"
    success "已回退到最后成功配置"
    return 0
  fi

  die "最后成功配置也不可用：$last_file"
}

tun_public_ip_without_proxy_env() {
  local ip route_dev

  route_dev="$(default_route_dev 2>/dev/null || true)"
  if [ -n "${route_dev:-}" ] && ! printf '%s\n' "$route_dev" | grep -Eiq '(tun|utun|mihomo|clash|meta)'; then
    ip="$(
      env \
        -u http_proxy \
        -u https_proxy \
        -u HTTP_PROXY \
        -u HTTPS_PROXY \
        -u all_proxy \
        -u ALL_PROXY \
        curl --interface "$route_dev" -fsSL --connect-timeout 3 --max-time 6 https://ip.sb 2>/dev/null \
        | head -n 1 \
        | tr -d '\r' \
        | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
    )"

    if [ -n "${ip:-}" ]; then
      echo "$ip"
      return 0
    fi
  fi

  env \
    -u http_proxy \
    -u https_proxy \
    -u HTTP_PROXY \
    -u HTTPS_PROXY \
    -u all_proxy \
    -u ALL_PROXY \
    curl -fsSL --connect-timeout 3 --max-time 6 https://ip.sb 2>/dev/null \
    | head -n 1 \
    | tr -d '\r' \
    | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

tun_public_ip_with_current_route() {
  env \
    -u http_proxy \
    -u https_proxy \
    -u HTTP_PROXY \
    -u HTTPS_PROXY \
    -u all_proxy \
    -u ALL_PROXY \
    curl -fsSL --connect-timeout 3 --max-time 6 https://ip.sb 2>/dev/null \
    | head -n 1 \
    | tr -d '\r' \
    | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

tun_traffic_effective_check() {
  local host_ip current_ip

  host_ip="$(tun_public_ip_without_proxy_env 2>/dev/null || true)"
  current_ip="$(tun_public_ip_with_current_route 2>/dev/null || true)"

  if [ -z "${host_ip:-}" ]; then
    echo "host-ip-unavailable"
    return 1
  fi

  if [ -z "${current_ip:-}" ]; then
    echo "current-ip-unavailable"
    return 1
  fi

  if [ "$current_ip" != "$host_ip" ]; then
    echo "ok"
    return 0
  fi

  echo "traffic-same-as-host"
  return 1
}

tun_effective_check() {
  local config_tun_enabled controller_ok traffic_result

  config_tun_enabled="$(runtime_config_tun_enabled 2>/dev/null || true)"

  if [ "$(tun_enabled)" != "true" ]; then
    echo "disabled-in-state"
    return 1
  fi

  if [ "${config_tun_enabled:-false}" != "true" ]; then
    echo "disabled-in-runtime-config"
    return 1
  fi

  if ! status_is_running 2>/dev/null; then
    echo "runtime-not-running"
    return 1
  fi

  controller_ok="false"
  if proxy_controller_reachable 2>/dev/null; then
    controller_ok="true"
  fi

  if [ "$controller_ok" != "true" ]; then
    echo "controller-unreachable"
    return 1
  fi

  traffic_result="$(tun_traffic_effective_check 2>/dev/null || true)"
  [ -n "${traffic_result:-}" ] || traffic_result="traffic-unknown"

  if [ "$traffic_result" = "ok" ]; then
    echo "ok"
    return 0
  fi

  echo "$traffic_result"
  return 1
}

tun_disable_check() {
  local config_tun_enabled

  config_tun_enabled="$(runtime_config_tun_enabled 2>/dev/null || true)"

  if [ "$(tun_enabled)" = "true" ]; then
    echo "state-still-enabled"
    return 1
  fi

  if [ "${config_tun_enabled:-false}" = "true" ]; then
    echo "runtime-config-still-enabled"
    return 1
  fi

  if status_is_running 2>/dev/null; then
    if ! proxy_controller_reachable 2>/dev/null; then
      echo "runtime-restarted-but-controller-unreachable"
      return 1
    fi
  fi

  echo "ok"
  return 0
}

wait_runtime_controller_ready() {
  local max_try="${1:-8}"
  local i=0

  while [ "$i" -lt "$max_try" ]; do
    if proxy_controller_reachable 2>/dev/null; then
      return 0
    fi

    sleep 1
    i=$((i + 1))
  done

  return 1
}

start_runtime() {
  local config_file="$RUNTIME_DIR/config.yaml"

  resolve_runtime_kernel
  if [ -s "$config_file" ]; then
    ensure_mihomo_geodata_ready "$config_file" || die "因 GEOIP 依赖未就绪，当前配置无法启动：$config_file"
  fi

  ensure_runtime_config_ready
  ensure_mihomo_geodata_ready "$config_file" || die "因 GEOIP 依赖未就绪，当前配置无法启动：$config_file"

  if [ -f "$RUNTIME_DIR/mihomo.pid" ]; then
    local old_pid
    old_pid="$(cat "$RUNTIME_DIR/mihomo.pid" 2>/dev/null || true)"
    if [ -n "${old_pid:-}" ] && kill -0 "$old_pid" 2>/dev/null; then
      if proxy_controller_reachable 2>/dev/null; then
        warn "Mihomo 已在运行：pid=$old_pid"
        return 0
      fi

      warn "Mihomo 进程仍在运行但控制器不可访问，正在重启以加载当前配置"
      stop_runtime || true
    else
      rm -f "$RUNTIME_DIR/mihomo.pid"
    fi
  fi

  nohup "$(runtime_kernel_bin)" -f "$config_file" -d "$RUNTIME_DIR" \
    > "$LOG_DIR/mihomo.out.log" 2>&1 &

  echo $! > "$RUNTIME_DIR/mihomo.pid"

  if ! wait_runtime_controller_ready 8; then
    warn "$(runtime_kernel_name) 已启动，但控制器未在预期时间内可访问"
    local new_pid
    new_pid="$(cat "$RUNTIME_DIR/mihomo.pid" 2>/dev/null || true)"
    [ -n "${new_pid:-}" ] && kill -0 "$new_pid" 2>/dev/null || return 1
  fi

  success "$(runtime_kernel_name) 已启动：pid=$(cat "$RUNTIME_DIR/mihomo.pid")"
}

stop_runtime() {
  local pid_file="$RUNTIME_DIR/mihomo.pid"

  [ -f "$pid_file" ] || {
    warn "Mihomo 当前未运行"
    return 0
  }

  local pid
  pid="$(cat "$pid_file" 2>/dev/null || true)"

  if [ -n "${pid:-}" ] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    sleep 1
    kill -9 "$pid" 2>/dev/null || true
  fi

  rm -f "$pid_file"
  success "Mihomo 已停止"
}

runtime_status_text() {
  if [ -f "$RUNTIME_DIR/mihomo.pid" ]; then
    local pid
    pid="$(cat "$RUNTIME_DIR/mihomo.pid" 2>/dev/null || true)"
    if [ -n "${pid:-}" ] && kill -0 "$pid" 2>/dev/null; then
      echo "运行中"
      echo "进程号：$pid"
      return 0
    fi
  fi

  echo "未运行"
}

clean_runtime_state() {
  stop_subconverter || true
  stop_runtime || true
  clear_build_meta || true
  clear_runtime_event_file || true

  rm -f "$RUNTIME_DIR/config.yaml" 2>/dev/null || true
  rm -f "$(runtime_meta_file)" 2>/dev/null || true
  rm -f "$RUNTIME_DIR"/*.pid 2>/dev/null || true
  rm -f "$RUNTIME_DIR"/*.lock 2>/dev/null || true

  rm -rf "$LOG_DIR" 2>/dev/null || true
  mkdir -p "$LOG_DIR"

  rm -rf "$RUNTIME_DIR/profiles" 2>/dev/null || true
  rm -rf "$RUNTIME_DIR/generated" 2>/dev/null || true
  rm -rf "$RUNTIME_DIR/tmp" 2>/dev/null || true
  rm -rf "$(runtime_dashboard_dir)" 2>/dev/null || true
  clear_shell_proxy_persist_state || true

  mkdir -p "$RUNTIME_DIR" "$BIN_DIR" "$LOG_DIR"
}
