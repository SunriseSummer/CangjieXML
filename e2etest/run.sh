#!/usr/bin/env bash
# e2e 入口：生成 fixture → 跑两端 probe → diff。任一步非 0 立即失败。
#
# 可以从仓库任意位置调用：脚本内自动切到仓库根再执行。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

FIXTURES_DIR="${REPO_ROOT}/e2etest/fixtures"
OUT_DIR="${REPO_ROOT}/e2etest/out"
PROBE_DIR="${REPO_ROOT}/e2etest/cangjie_probe"
PROBE_BIN="${PROBE_DIR}/target/release/bin/main"

mkdir -p "${OUT_DIR}"

# --- 0. 仓颉 SDK 环境（若未加载则加载；允许调用方预先 source 好）----------
# envsetup.sh 会引用若干未初始化的环境变量（如 LD_LIBRARY_PATH），会被
# `set -u` 拒绝——临时关掉，source 完再开。
if ! command -v cjc >/dev/null 2>&1; then
  if [ -f /opt/cangjie/envsetup.sh ]; then
    set +u
    # shellcheck disable=SC1091
    source /opt/cangjie/envsetup.sh
    set -u
  else
    echo "error: cjc not on PATH and /opt/cangjie/envsetup.sh not found" >&2
    exit 2
  fi
fi

# --- 1. 生成 fixture ------------------------------------------------------
echo "[e2e] (1/4) generating fixtures"
python3 "${SCRIPT_DIR}/fixtures/generate.py"

# --- 2. 构建仓颉 probe ----------------------------------------------------
echo "[e2e] (2/4) building cangjie probe"
(cd "${PROBE_DIR}" && cjpm build >/dev/null)

# --- 3. 跑两端 probe ------------------------------------------------------
echo "[e2e] (3/4) running probes"
python3 "${SCRIPT_DIR}/python_probe/probe.py" "${FIXTURES_DIR}" "${OUT_DIR}/python.json"
"${PROBE_BIN}" "${FIXTURES_DIR}" "${OUT_DIR}/cangjie.json"

# --- 4. diff --------------------------------------------------------------
echo "[e2e] (4/4) diffing fingerprints"
python3 "${SCRIPT_DIR}/diff.py" "${OUT_DIR}/python.json" "${OUT_DIR}/cangjie.json"
