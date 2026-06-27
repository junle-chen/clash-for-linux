#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEEP_RUNTIME="false"
PURGE_RUNTIME="false"
DEV_RESET="false"
REMOVE_PROJECT="false"
ASSUME_YES="false"

for arg in "$@"; do
  case "$arg" in
    --keep-runtime)
      KEEP_RUNTIME="true"
      ;;
    --purge-runtime)
      # Compatibility alias: complete uninstall is the default now, but older
      # docs/scripts may still pass --purge-runtime explicitly.
      PURGE_RUNTIME="true"
      KEEP_RUNTIME="false"
      ;;
    --dev-reset)
      DEV_RESET="true"
      ;;
    --remove-project)
      REMOVE_PROJECT="true"
      ;;
    --yes|-y)
      ASSUME_YES="true"
      ;;
    *)
      echo "未知参数：$arg" >&2
      echo "用法：bash uninstall.sh [--keep-runtime] [--dev-reset] [--purge-runtime] [--remove-project] [--yes]" >&2
      exit 2
      ;;
  esac
done

if [ "$REMOVE_PROJECT" = "true" ] && { [ "$KEEP_RUNTIME" = "true" ] || [ "$DEV_RESET" = "true" ]; }; then
  echo "--remove-project 不能与 --keep-runtime 或 --dev-reset 同时使用" >&2
  exit 2
fi

source "$PROJECT_DIR/scripts/core/common.sh"
source "$PROJECT_DIR/scripts/core/runtime.sh"
source "$PROJECT_DIR/scripts/core/config.sh"
source "$PROJECT_DIR/scripts/core/proxy.sh"
source "$PROJECT_DIR/scripts/init/systemd.sh"
source "$PROJECT_DIR/scripts/init/systemd-user.sh"
source "$PROJECT_DIR/scripts/init/script.sh"

print_current_shell_proxy_cleanup_hint() {
  echo
  echo "如果当前终端仍然存在代理变量，请执行："
  echo "unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY no_proxy NO_PROXY"
}

print_uninstall_modes_hint() {
  echo
  echo "其他卸载方式："
  echo "  bash uninstall.sh --keep-runtime   # 只移除入口，保留 runtime 数据"
  echo "  bash uninstall.sh --dev-reset      # 开发重置，保留订阅与下载缓存"
  echo "  bash uninstall.sh --remove-project # 完整卸载后移走项目目录"
}

confirm_remove_project() {
  local answer

  [ "$ASSUME_YES" = "true" ] && return 0

  if [ ! -t 0 ]; then
    echo "--remove-project 需要交互确认；非交互场景请显式传入 --yes" >&2
    return 1
  fi

  echo
  echo "即将完整卸载并移走项目目录：$PROJECT_DIR"
  echo "请输入完整项目路径确认："
  IFS= read -r answer
  [ "$answer" = "$PROJECT_DIR" ]
}

remove_project_dir() {
  local backup_root backup_dir parent_dir

  case "$PROJECT_DIR" in
    ""|"/"|"$HOME"|"$HOME/")
      echo "拒绝移走危险路径：$PROJECT_DIR" >&2
      return 1
      ;;
  esac

  [ -f "$PROJECT_DIR/install.sh" ] || {
    echo "拒绝移走非项目目录：$PROJECT_DIR" >&2
    return 1
  }
  [ -f "$PROJECT_DIR/uninstall.sh" ] || {
    echo "拒绝移走非项目目录：$PROJECT_DIR" >&2
    return 1
  }
  [ -f "$PROJECT_DIR/scripts/core/common.sh" ] || {
    echo "拒绝移走非项目目录：$PROJECT_DIR" >&2
    return 1
  }

  backup_root="${CLASH_REMOVE_PROJECT_BACKUP_ROOT:-$HOME/.local/share/clash-for-linux-backups}"
  mkdir -p "$backup_root"
  backup_dir="$backup_root/project.removed-$(date +%Y%m%d-%H%M%S)"
  if [ -e "$backup_dir" ]; then
    backup_dir="$backup_dir-$$"
  fi

  parent_dir="$(dirname "$PROJECT_DIR")"
  cd "$parent_dir"
  mv "$PROJECT_DIR" "$backup_dir"
  echo "[ok] 已移走项目目录：$backup_dir"
}

init_project_context "$PROJECT_DIR"
load_env_if_exists
detect_install_scope auto

if [ "$REMOVE_PROJECT" = "true" ]; then
  confirm_remove_project || {
    echo "已取消移走项目目录" >&2
    exit 1
  }
fi

SYSTEM_PROXY_CLOSED="unknown"
if boot_proxy_keep_disable; then
  SYSTEM_PROXY_CLOSED="true"
else
  SYSTEM_PROXY_CLOSED="false"
fi

clear_shell_proxy_persist_state || true
stop_subconverter >/dev/null 2>&1 || true
service_stop >/dev/null 2>&1 || true
stop_runtime >/dev/null 2>&1 || true
remove_runtime_entry >/dev/null 2>&1 || true
remove_clashctl_entry >/dev/null 2>&1 || true
remove_clashctl_completion >/dev/null 2>&1 || true
remove_shell_alias_entry >/dev/null 2>&1 || true

if [ "$DEV_RESET" = "true" ] && [ "$PURGE_RUNTIME" != "true" ]; then
  KEEP_RUNTIME="true"
fi

if [ "$KEEP_RUNTIME" != "true" ]; then
  rm -rf "$RUNTIME_DIR"
  clear_controller_secret || true
  print_current_shell_proxy_cleanup_hint
  echo "[ok] 已删除运行目录：$RUNTIME_DIR"
  if [ "$SYSTEM_PROXY_CLOSED" = "true" ]; then
    echo "[ok] 已关闭系统代理持久接管"
  else
    echo "[warn] 未能确认系统代理持久块已关闭，请检查：$(system_proxy_env_file)"
  fi
  echo "[ok] 完整卸载：已清理服务、入口、运行目录与 controller secret"
  print_uninstall_modes_hint
elif [ "$DEV_RESET" = "true" ]; then
  cache_backup_dir="$(mktemp -d)"
  cache_restore_needed="false"
  subscriptions_backup_file="$cache_backup_dir/subscriptions.yaml"
  subscriptions_restore_needed="false"

  if [ -d "$RUNTIME_DIR/cache" ]; then
    cp -a "$RUNTIME_DIR/cache" "$cache_backup_dir/" 2>/dev/null || true
    cache_restore_needed="true"
  fi

  if [ -f "$RUNTIME_DIR/subscriptions.yaml" ]; then
    cp -f "$RUNTIME_DIR/subscriptions.yaml" "$subscriptions_backup_file" 2>/dev/null || true
    subscriptions_restore_needed="true"
  fi

  clean_runtime_state >/dev/null 2>&1

  if [ "$cache_restore_needed" = "true" ] && [ -d "$cache_backup_dir/cache" ]; then
    mkdir -p "$RUNTIME_DIR"
    rm -rf "$RUNTIME_DIR/cache" 2>/dev/null || true
    mv "$cache_backup_dir/cache" "$RUNTIME_DIR/cache"
  fi

  if [ "$subscriptions_restore_needed" = "true" ] && [ -f "$subscriptions_backup_file" ]; then
    mkdir -p "$RUNTIME_DIR"
    cp -f "$subscriptions_backup_file" "$RUNTIME_DIR/subscriptions.yaml"
  fi

  rm -rf "$cache_backup_dir" 2>/dev/null || true
  clear_controller_secret || true
  print_current_shell_proxy_cleanup_hint

  echo "[ok] 已清理安装状态：$RUNTIME_DIR"
  echo "[info] 保留内容：subscriptions.yaml、下载缓存与项目目录仍在（已清理 controller secret）"
else
  print_current_shell_proxy_cleanup_hint
  echo "[ok] 已卸载安装入口，保留运行目录：$RUNTIME_DIR"
  echo "[info] 保留内容：runtime 数据仍在（按 --keep-runtime 请求）"
fi

echo "[ok] 卸载完成"

if [ "$REMOVE_PROJECT" = "true" ]; then
  remove_project_dir
fi
