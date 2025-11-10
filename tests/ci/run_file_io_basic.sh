#!/usr/bin/env bash
set -euo pipefail

WORKSPACE="$(pwd)"
CRATE_DIR="${WORKSPACE}/tests/ci/cases"
LOG_DIR="${WORKSPACE}/logs/ci"
TARGET_DIR="${WORKSPACE}/target/ci-cases"
BINARY_NAME="file_io_basic"

DISK_IMAGE="/home/sunhaosheng/x-kernel/arceos/disk.img"
TARGET_TRIPLE="${CROSS_TARGET:-aarch64-unknown-linux-musl}"

mkdir -p "${LOG_DIR}"
export CARGO_TARGET_DIR="${TARGET_DIR}"

HOST_BIN="${TARGET_DIR}/release/${BINARY_NAME}"
TARGET_BIN="${TARGET_DIR}/${TARGET_TRIPLE}/release/${BINARY_NAME}"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="${LOG_DIR}/file-io-basic-${TIMESTAMP}.log"

if [[ ! -f "${CRATE_DIR}/Cargo.toml" ]]; then
  echo "[error] 未找到 Rust 测试工程 ${CRATE_DIR}" >&2
  exit 1
fi

echo "[info] 构建 ${BINARY_NAME} (host)" >&2
cargo build --manifest-path "${CRATE_DIR}/Cargo.toml" --release --bin "${BINARY_NAME}"

if [[ ! -x "${HOST_BIN}" ]]; then
  echo "[error] 构建后未找到主机可执行文件 ${HOST_BIN}" >&2
  exit 1
fi

echo "[info] 运行 host 版本 -> ${LOG_FILE}" >&2
if ! "${HOST_BIN}" | tee "${LOG_FILE}"; then
  echo "[error] file_io_basic 主机版执行失败，详见 ${LOG_FILE}" >&2
  exit 1
fi

echo "[info] 主机日志保存在 ${LOG_FILE}" >&2

if [[ "${SKIP_DISK_IMAGE:-0}" == "1" ]]; then
  echo "[info] SKIP_DISK_IMAGE=1，跳过写入磁盘镜像步骤" >&2
  exit 0
fi

if [[ ! -f "${DISK_IMAGE}" ]]; then
  echo "[error] 未找到磁盘镜像: ${DISK_IMAGE}" >&2
  exit 1
fi

if [[ ! -w "${DISK_IMAGE}" ]]; then
  echo "[error] 当前用户无权写入磁盘镜像 ${DISK_IMAGE}" >&2
  exit 1
fi

if ! command -v debugfs >/dev/null 2>&1; then
  echo "[error] 未检测到 debugfs，请安装 e2fsprogs" >&2
  exit 1
fi

if ! rustup target list --installed | grep -q "^${TARGET_TRIPLE}$"; then
  echo "[info] 安装 Rust 目标 ${TARGET_TRIPLE}" >&2
  rustup target add "${TARGET_TRIPLE}"
fi

echo "[info] 构建 ${BINARY_NAME} (${TARGET_TRIPLE})" >&2
cargo build \
  --manifest-path "${CRATE_DIR}/Cargo.toml" \
  --release \
  --bin "${BINARY_NAME}" \
  --target "${TARGET_TRIPLE}"

if [[ ! -f "${TARGET_BIN}" ]]; then
  echo "[error] 未找到交叉编译产物 ${TARGET_BIN}" >&2
  exit 1
fi

DEST_PATH="/usr/tests/${BINARY_NAME}"
echo "[info] 写入磁盘镜像 -> ${DEST_PATH}" >&2
debugfs -w "${DISK_IMAGE}" -R "mkdir /usr" >/dev/null 2>&1 || true
debugfs -w "${DISK_IMAGE}" -R "mkdir /usr/tests" >/dev/null 2>&1 || true
debugfs -w "${DISK_IMAGE}" -R "unlink ${DEST_PATH}" >/dev/null 2>&1 || true
debugfs -w "${DISK_IMAGE}" -R "write ${TARGET_BIN} ${DEST_PATH}"
debugfs -w "${DISK_IMAGE}" -R "chmod 755 ${DEST_PATH}" >/dev/null

echo "[info] file_io_basic 已写入磁盘镜像 ${DEST_PATH}" >&2
