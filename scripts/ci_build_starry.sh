#!/usr/bin/env bash
set -euo pipefail

SUITE=${1:-ci-test}
ARCH=${ARCH:-aarch64}
STARRYOS_ROOT=${STARRYOS_ROOT:-../StarryOS}
ENABLE_STARRYOS_BUILD=${ENABLE_STARRYOS_BUILD:-0}
ARTIFACT_DIR="artifacts/${SUITE}"
mkdir -p "${ARTIFACT_DIR}"

ts() {
  date -u +%Y%m%d-%H%M%S
}

log() {
  echo "[build:starry] $*" >&2
}

write_metadata() {
  cat >"${ARTIFACT_DIR}/build.info" <<META
suite=${SUITE}
arch=${ARCH}
stamp=$(ts)
starryos_root=${STARRYOS_ROOT}
META
}

if [[ "${ENABLE_STARRYOS_BUILD}" != "1" ]]; then
  log "跳过真实 StarryOS 构建 (设置 ENABLE_STARRYOS_BUILD=1 可启用)"
  write_metadata
  exit 0
fi

if [[ ! -d "${STARRYOS_ROOT}" ]]; then
  log "未找到 StarryOS 目录: ${STARRYOS_ROOT}"
  exit 1
fi

pushd "${STARRYOS_ROOT}" >/dev/null
log "开始 make ARCH=${ARCH} build"
make ARCH="${ARCH}" build
log "生成 rootfs 镜像"
make ARCH="${ARCH}" img
popd >/dev/null

if compgen -G "${STARRYOS_ROOT}/StarryOS_${ARCH}*-qemu-virt.bin" > /dev/null; then
  for bin in "${STARRYOS_ROOT}"/StarryOS_"${ARCH}"*-qemu-virt.bin; do
    cp "${bin}" "${ARTIFACT_DIR}/" || true
  done
fi

write_metadata
log "StarryOS 构建完成，产物位于 ${ARTIFACT_DIR}"
