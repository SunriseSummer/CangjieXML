#!/usr/bin/env bash
# xlsx_to_csv 的入口脚本：构建本项目，再把 excel/ 目录里的 xlsx 文件逐个
# 转成 CSV，落在 excel/csv_out/<xlsx 基名>/ 下。
#
# 典型用法（项目根目录）：
#
#     bash excel/xlsx_to_csv/run.sh
#
# 调用方可以预先 source 好仓颉 SDK 的 envsetup.sh；没 source 则自动探测
# /opt/cangjie/envsetup.sh。其它位置的 SDK 请自行 source 后再跑。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXCEL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUT_ROOT="${EXCEL_DIR}/csv_out"
BIN="${SCRIPT_DIR}/target/release/bin/main"

# --- 0. 仓颉 SDK 环境 ------------------------------------------------------
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

# --- 1. 构建 --------------------------------------------------------------
echo "[xlsx_to_csv] building"
(cd "${SCRIPT_DIR}" && cjpm build >/dev/null)

# --- 2. 遍历所有 xlsx ------------------------------------------------------
shopt -s nullglob
xlsx_files=( "${EXCEL_DIR}"/*.xlsx )
if [ "${#xlsx_files[@]}" -eq 0 ]; then
  echo "warning: no .xlsx files under ${EXCEL_DIR}" >&2
  exit 0
fi

mkdir -p "${OUT_ROOT}"
for xlsx in "${xlsx_files[@]}"; do
  base="$(basename "${xlsx}" .xlsx)"
  out_dir="${OUT_ROOT}/${base}"
  rm -rf "${out_dir}"
  echo "[xlsx_to_csv] processing ${xlsx} -> ${out_dir}"
  "${BIN}" "${xlsx}" "${out_dir}"
done

echo "[xlsx_to_csv] done. CSVs under ${OUT_ROOT}"
