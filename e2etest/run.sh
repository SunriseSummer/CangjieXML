#!/usr/bin/env bash
# e2e 入口：生成 fixture → 跑 Python 侧 probe → 多模式跑仓颉 probe → 逐模式 diff。
# 任一步非 0 立即失败。
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
echo "[e2e] (1/5) generating fixtures"
python3 "${SCRIPT_DIR}/fixtures/generate.py"

# --- 2. 构建仓颉 probe ----------------------------------------------------
echo "[e2e] (2/5) building cangjie probe"
(cd "${PROBE_DIR}" && cjpm build >/dev/null)

# --- 3. 跑 Python 侧 probe（唯一"真相源"）--------------------------------
echo "[e2e] (3/5) running python probe"
python3 "${SCRIPT_DIR}/python_probe/probe.py" "${FIXTURES_DIR}" "${OUT_DIR}/python.json"

# --- 4. 跑仓颉 probe 的多模式流水线 --------------------------------------
# 每种模式产出独立 JSON，与 python.json 分别 diff；任一模式挂即整体挂。
# - parse              ：loadXmlFromFile → fingerprint（覆盖 Parser + IO）
# - roundtrip-pretty   ：parse → write(default pretty) → parse → fingerprint
# - roundtrip-compact  ：parse → write(compact) → parse → fingerprint
# - builder            ：XmlDocumentBuilder 构造 01_bookstore → 写 → 解析 → 指纹
# - bytes              ：parseXmlBytes → writeXmlToBytes → parseXmlBytes → 指纹
echo "[e2e] (4/5) running cangjie probes (parse / roundtrip-pretty / roundtrip-compact / bytes / builder)"
"${PROBE_BIN}" parse              "${FIXTURES_DIR}" "${OUT_DIR}/cangjie.parse.json"
"${PROBE_BIN}" roundtrip-pretty   "${FIXTURES_DIR}" "${OUT_DIR}/cangjie.roundtrip_pretty.json"
"${PROBE_BIN}" roundtrip-compact  "${FIXTURES_DIR}" "${OUT_DIR}/cangjie.roundtrip_compact.json"
"${PROBE_BIN}" bytes              "${FIXTURES_DIR}" "${OUT_DIR}/cangjie.bytes.json"
"${PROBE_BIN}" builder            "${FIXTURES_DIR}" "${OUT_DIR}/cangjie.builder.json"

# --- 5. diff --------------------------------------------------------------
# Builder 模式只产出 01_bookstore.xml 一条记录，所以传 --subset 让 diff 按交集比较。
echo "[e2e] (5/5) diffing fingerprints"
python3 "${SCRIPT_DIR}/diff.py" "${OUT_DIR}/python.json" "${OUT_DIR}/cangjie.parse.json"            --label parse
python3 "${SCRIPT_DIR}/diff.py" "${OUT_DIR}/python.json" "${OUT_DIR}/cangjie.roundtrip_pretty.json"  --label roundtrip-pretty
python3 "${SCRIPT_DIR}/diff.py" "${OUT_DIR}/python.json" "${OUT_DIR}/cangjie.roundtrip_compact.json" --label roundtrip-compact
python3 "${SCRIPT_DIR}/diff.py" "${OUT_DIR}/python.json" "${OUT_DIR}/cangjie.bytes.json"             --label bytes
python3 "${SCRIPT_DIR}/diff.py" "${OUT_DIR}/python.json" "${OUT_DIR}/cangjie.builder.json"           --label builder --subset

