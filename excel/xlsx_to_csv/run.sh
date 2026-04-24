#!/usr/bin/env bash
# xlsx_to_csv 的入口脚本：构建本项目，再把 excel/ 目录里的 xlsx 文件逐个
# 转成 CSV，落在 excel/csv_out/<xlsx 基名>/ 下。
#
# 典型用法（项目根目录）：
#
#     bash excel/xlsx_to_csv/run.sh
#
# 先决条件：
#
#   1. 已安装并配置仓颉 SDK 1.0.5，`cjc` 与 `cjpm` 可在 PATH 上找到
#      （自行 source 对应的 `envsetup.sh`）。
#   2. 系统具备 `curl` 与 `unzip`——仅用来首次下载 stdx 发行包；运行时解压
#      xlsx 走的是仓颉纯代码路径，不依赖宿主 `unzip`。
#
# Windows 用户请参考 README 手动下载 stdx 并解压到 `excel/xlsx_to_csv/stdx/`，
# 然后 `cjpm build` 即可，本脚本不在 Windows 上运行。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXCEL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUT_ROOT="${EXCEL_DIR}/csv_out"
STDX_DIR="${SCRIPT_DIR}/stdx"
STDX_URL_DEFAULT="https://github.com/SunriseSummer/CangjieSDK/releases/download/1.0.5/cangjie-stdx-linux-x64-1.0.5.1.zip"
STDX_URL="${CANGJIE_STDX_URL:-${STDX_URL_DEFAULT}}"
BIN="${SCRIPT_DIR}/target/release/bin/main"

# --- 0. 仓颉 SDK 环境 ------------------------------------------------------
if ! command -v cjc >/dev/null 2>&1 || ! command -v cjpm >/dev/null 2>&1; then
  echo "error: cjc/cjpm not on PATH; please install Cangjie SDK 1.0.5 and source its envsetup.sh" >&2
  exit 2
fi

# --- 1. 确保 stdx 已就位 ---------------------------------------------------
# cjpm.toml 把 `./stdx/dynamic/stdx` 作为 bin-dependencies 路径，下面的脚本
# 只在该目录缺失时才触发下载，其它环境（比如离线）可以事先手工解压到同样
# 位置。
if [ ! -d "${STDX_DIR}/dynamic/stdx" ]; then
  echo "[xlsx_to_csv] stdx not found at ${STDX_DIR}, downloading from ${STDX_URL}"
  mkdir -p "${STDX_DIR}"
  tmp_zip="$(mktemp -t cangjie-stdx.XXXXXX.zip)"
  trap 'rm -f "${tmp_zip}"' EXIT
  curl -fL "${STDX_URL}" -o "${tmp_zip}"
  unzip -q -o "${tmp_zip}" -d "${STDX_DIR}"
  # 发行包顶层可能是 `stdx/` 也可能直接是 `dynamic/`、`static/`；归一成
  # `${STDX_DIR}/dynamic/stdx`。
  if [ ! -d "${STDX_DIR}/dynamic/stdx" ] && [ -d "${STDX_DIR}/stdx/dynamic/stdx" ]; then
    mv "${STDX_DIR}/stdx/"* "${STDX_DIR}/"
    rmdir "${STDX_DIR}/stdx" 2>/dev/null || true
  fi
  if [ ! -d "${STDX_DIR}/dynamic/stdx" ]; then
    echo "error: stdx layout not recognized; expected ${STDX_DIR}/dynamic/stdx/" >&2
    exit 2
  fi
fi

# --- 2. 构建 --------------------------------------------------------------
echo "[xlsx_to_csv] building"
(cd "${SCRIPT_DIR}" && cjpm build >/dev/null)

# --- 3. 遍历所有 xlsx ------------------------------------------------------
shopt -s nullglob
xlsx_files=( "${EXCEL_DIR}"/*.xlsx )
if [ "${#xlsx_files[@]}" -eq 0 ]; then
  echo "warning: no .xlsx files under ${EXCEL_DIR}" >&2
  exit 0
fi

mkdir -p "${OUT_ROOT}"
export LD_LIBRARY_PATH="${STDX_DIR}/dynamic/stdx${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
for xlsx in "${xlsx_files[@]}"; do
  base="$(basename "${xlsx}" .xlsx)"
  out_dir="${OUT_ROOT}/${base}"
  rm -rf "${out_dir}"
  echo "[xlsx_to_csv] processing ${xlsx} -> ${out_dir}"
  "${BIN}" "${xlsx}" "${out_dir}"
done

echo "[xlsx_to_csv] done. CSVs under ${OUT_ROOT}"
