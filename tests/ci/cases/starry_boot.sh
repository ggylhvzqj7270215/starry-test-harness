#!/usr/bin/env bash
set -euo pipefail

ARCH=${ARCH:-aarch64}
STARRYOS_ROOT=${STARRYOS_ROOT:-../StarryOS}
ENABLE_STARRYOS_BOOT=${ENABLE_STARRYOS_BOOT:-0}
CI_TEST_SCRIPT="${STARRYOS_ROOT}/scripts/ci-test.py"

if [[ "${ENABLE_STARRYOS_BOOT}" != "1" ]]; then
  echo "[starry-boot] 跳过实际 QEMU 启动 (设置 ENABLE_STARRYOS_BOOT=1 可启用)"
  exit 0
fi

if [[ ! -x "${CI_TEST_SCRIPT}" ]]; then
  echo "[starry-boot] 未找到 ci-test.py, 请确保 STARRYOS_ROOT=${STARRYOS_ROOT}" >&2
  exit 1
fi

python3 "${CI_TEST_SCRIPT}" "${ARCH}"
