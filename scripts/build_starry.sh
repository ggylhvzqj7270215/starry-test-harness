#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

SUITE=${1:-ci-test}
ARCH=${ARCH:-aarch64}

# ===============================
# 目录准备
# ===============================
ARTIFACT_DIR="${REPO_ROOT}/artifacts/${SUITE}"
LOG_FILE="${ARTIFACT_DIR}/build.log"
mkdir -p "${ARTIFACT_DIR}"
: > "${LOG_FILE}"
exec > >(tee -a "${LOG_FILE}") 2>&1

log() {
  echo "[build:starry] $*"
}

# ===============================
# CI 模式：不 clone，不 checkout
# ===============================
if [[ "${SKIP_STARRY_BUILD:-}" == "1" ]]; then
  log "SKIP_STARRY_BUILD=1 → 使用 CI checkout 的 StarryOS"
  log "STARRYOS_ROOT=${STARRYOS_ROOT}"

  if [[ ! -d "${STARRYOS_ROOT}/.git" ]]; then
    log "ERROR: STARRYOS_ROOT 不是 Git 仓库，CI checkout 有问题"
    exit 1
  fi

  # 使用 CI 给的 commit
  STARRYOS_COMMIT="${STARRYOS_COMMIT:?SKIP 模式必须提供 STARRYOS_COMMIT}"

else
  # ===============================
  # 本地模式：自动 clone / update
  # ===============================
  STARRYOS_REMOTE="${STARRYOS_REMOTE:-https://github.com/Starry-OS/StarryOS.git}"
  STARRYOS_COMMIT="${STARRYOS_COMMIT:-main}"
  STARRYOS_ROOT="${STARRYOS_ROOT:-${REPO_ROOT}/.cache/StarryOS}"

  if [[ "${STARRYOS_ROOT}" != /* ]]; then
    STARRYOS_ROOT="${REPO_ROOT}/${STARRYOS_ROOT}"
  fi

  log "本地模式：从远端 clone/update StarryOS"
  log "REMOTE=${STARRYOS_REMOTE}"
  log "COMMIT=${STARRYOS_COMMIT}"
  log "ROOT=${STARRYOS_ROOT}"

  mkdir -p "$(dirname "${STARRYOS_ROOT}")"

  if [[ ! -d "${STARRYOS_ROOT}/.git" ]]; then
    log "Cloning StarryOS..."
    git clone --recursive "${STARRYOS_REMOTE}" "${STARRYOS_ROOT}"
  else
    log "Updating StarryOS..."
    git -C "${STARRYOS_ROOT}" fetch origin --tags --prune
  fi

  git -C "${STARRYOS_ROOT}" checkout "${STARRYOS_COMMIT}"
  git -C "${STARRYOS_ROOT}" submodule update --init --recursive
fi

# ===============================
# 显示最终 commit
# ===============================
STARRYOS_COMMIT_REAL=$(git -C "${STARRYOS_ROOT}" rev-parse HEAD)
log "StarryOS commit = ${STARRYOS_COMMIT_REAL}"

# ===============================
# Rust Toolchain 环境检查
# ===============================
if ! command -v rustup >/dev/null 2>&1; then
  log "ERROR: rustup 未安装"
  exit 1
fi

log "Rust toolchain 受 StarryOS/rust-toolchain.toml 自动管理"

ACTIVE_TOOLCHAIN="$(rustup show active-toolchain 2>/dev/null | tr -d '\r')"
log "Active toolchain = ${ACTIVE_TOOLCHAIN}"

# ===============================
# 编译 StarryOS
# ===============================
log "Building StarryOS (ARCH=${ARCH})"
make -C "${STARRYOS_ROOT}" ARCH="${ARCH}" build

# ===============================
# rootfs 缓存支持
# ===============================
ROOTFS_CACHE_DIR="${ROOTFS_CACHE_DIR:-${REPO_ROOT}/.cache/rootfs}"
mkdir -p "${ROOTFS_CACHE_DIR}"

IMG_VERSION="${ROOTFS_VERSION:-20250917}"
IMG="rootfs-${ARCH}.img"
IMG_URL="https://github.com/Starry-OS/rootfs/releases/download/${IMG_VERSION}"
IMG_PATH="${ROOTFS_CACHE_DIR}/${IMG}"

log "确保 rootfs 模板存在：${IMG_PATH}"

if [[ ! -f "${IMG_PATH}" ]]; then
  log "下载 rootfs 模板：${IMG}"
  curl -f -L "${IMG_URL}/${IMG}.xz" -o "${IMG_PATH}.xz"
  xz -d "${IMG_PATH}.xz"
fi

log "rootfs OK"

# 拷贝 rootfs 给 StarryOS（供 QEMU 用）
STARRYOS_IMG="${STARRYOS_ROOT}/${IMG}"
if [[ ! -f "${STARRYOS_IMG}" ]] || [[ "${IMG_PATH}" -nt "${STARRYOS_IMG}" ]]; then
  log "复制 rootfs 到 StarryOS 目录"
  cp "${IMG_PATH}" "${STARRYOS_IMG}"
fi

# ===============================
# 拷贝 StarryOS 编译产物
# ===============================
log "复制构建产物到 ${ARTIFACT_DIR}"

shopt -s nullglob
for artifact in "${STARRYOS_ROOT}/"StarryOS_"${ARCH}"*-qemu-virt.*; do
  cp "${artifact}" "${ARTIFACT_DIR}/"
  log "  -> $(basename "${artifact}")"
done
shopt -u nullglob

# ===============================
# 生成 metadata (build.info)
# ===============================
cat > "${ARTIFACT_DIR}/build.info" <<META
suite=${SUITE}
arch=${ARCH}
stamp=$(date -u +%Y%m%d-%H%M%S)
starryos_remote=${STARRYOS_REMOTE:-CI}
starryos_commit=${STARRYOS_COMMIT_REAL}
starryos_root=${STARRYOS_ROOT}
META

log "StarryOS 构建完成"
