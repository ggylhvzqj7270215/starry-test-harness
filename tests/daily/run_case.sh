#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <case-id> [args...]" >&2
  exit 1
fi

CASE_ID="$1"
shift || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="${STARRY_WORKSPACE_ROOT:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"
CASE_DIR="${SCRIPT_DIR}/cases/${CASE_ID}"

if [[ ! -d "${CASE_DIR}" ]]; then
  echo "[daily] case directory not found: ${CASE_DIR}" >&2
  exit 1
fi

MANIFEST_PATH="${CASE_DIR}/Cargo.toml"
if [[ ! -f "${MANIFEST_PATH}" ]]; then
  echo "[daily] missing Cargo.toml in ${CASE_DIR}" >&2
  exit 1
fi

PACKAGE_NAME="$(
  cargo metadata \
    --manifest-path "${MANIFEST_PATH}" \
    --format-version 1 \
    --no-deps \
  | python3 -c 'import json, sys; print(json.load(sys.stdin)["packages"][0]["name"])'
)"

TARGET_DIR="${WORKSPACE_ROOT}/target/daily-cases"
ARTIFACT_DIR="${STARRY_CASE_ARTIFACT_DIR:-${CASE_DIR}/artifacts}"

mkdir -p "${TARGET_DIR}" "${ARTIFACT_DIR}"

echo "[daily] building ${PACKAGE_NAME}" >&2
CARGO_TARGET_DIR="${TARGET_DIR}" \
  cargo build --manifest-path "${MANIFEST_PATH}" --release

BIN_PATH="${TARGET_DIR}/release/${PACKAGE_NAME}"
if [[ ! -x "${BIN_PATH}" ]]; then
  echo "[daily] expected binary not found: ${BIN_PATH}" >&2
  exit 1
fi

RUN_STDOUT="${ARTIFACT_DIR}/stdout.json"
RUN_STDERR="${ARTIFACT_DIR}/stderr.log"
RESULT_PATH="${ARTIFACT_DIR}/result.json"

echo "[daily] running ${PACKAGE_NAME}" >&2
if ! OUTPUT="$("${BIN_PATH}" "$@" 2> >(tee "${RUN_STDERR}" >&2))"; then
  echo "[daily] binary execution failed" >&2
  exit 1
fi

printf "%s\n" "${OUTPUT}" | tee "${RUN_STDOUT}" >/dev/null

if [[ ! -s "${RUN_STDOUT}" ]]; then
  echo "[daily] run log empty - expected structured output" >&2
  exit 1
fi

python3 - "$RUN_STDOUT" "$RESULT_PATH" <<'PY'
import json
import sys
from pathlib import Path

log_path = Path(sys.argv[1])
result_path = Path(sys.argv[2])

try:
    data = json.loads(log_path.read_text())
except json.JSONDecodeError as exc:
    print(f"[daily] invalid JSON output: {exc}", file=sys.stderr)
    sys.exit(1)

status = data.get("status")
if status not in {"pass", "fail"}:
    print("[daily] missing 'status' field (pass|fail) in output", file=sys.stderr)
    sys.exit(1)

result_path.write_text(json.dumps(data, indent=2))
print(f"[daily] stored result -> {result_path}")

if status != "pass":
    sys.exit(2)
PY

