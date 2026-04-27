#!/usr/bin/env python3
"""
性能测试脚本——只负责跑基准并产出 JSON。

流程：
  1. 自动确保 `cjpm` 可用（必要时 source `/opt/cangjie/envsetup.sh`）。
  2. `python3 fixtures/generate.py`     —— 生成九份典型 XML（3 形态 × 3 规模）。
  3. `make -C tinyxml2_bench`            —— 构建 C++ 端探针。
  4. `cjpm build`（in cangjie_bench/）   —— 以 `-O2` 配置构建仓颉端探针。
  5. 串行跑三端探针，共享同一份 `plan.json`，输出三份 JSON 到 `out/`。

报告生成在 `report.py` 中，由 JSON 单独消费。
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

PERF_DIR     = Path(__file__).resolve().parent
FIXTURES_DIR = PERF_DIR / "fixtures"
PYTHON_BENCH = PERF_DIR / "python_bench" / "bench.py"
TINYXML2_DIR = PERF_DIR / "tinyxml2_bench"
CANGJIE_DIR  = PERF_DIR / "cangjie_bench"
OUT_DIR      = PERF_DIR / "out"
PLAN_PATH    = OUT_DIR / "plan.json"


# 各 fixture 的迭代次数——根据字节量与单次耗时调出来的，
# 目标：每个 (lib, scenario, fixture) 单元跑 0.05 ~ 5 秒之间。
ITERATIONS = {
    "catalog_small.xml":  500,
    "config_small.xml":   500,
    "deep_small.xml":     500,
    "catalog_medium.xml": 30,
    "config_medium.xml":  60,
    "deep_medium.xml":    200,
    "catalog_large.xml":  5,
    "config_large.xml":   10,
    "deep_large.xml":     50,
}

FIXTURE_ORDER = [
    "catalog_small.xml",  "catalog_medium.xml", "catalog_large.xml",
    "config_small.xml",   "config_medium.xml",  "config_large.xml",
    "deep_small.xml",     "deep_medium.xml",    "deep_large.xml",
]


def log(section: str) -> None:
    print(f"=== {section}", flush=True)


def run(cmd: list[str], *, cwd: Path | None = None) -> None:
    display = " ".join(cmd)
    where = f" (cwd={cwd})" if cwd is not None else ""
    print(f"$ {display}{where}", flush=True)
    res = subprocess.run(cmd, cwd=cwd)
    if res.returncode != 0:
        raise SystemExit(res.returncode)


def ensure_cjpm_available() -> None:
    """缺 cjpm 就 source envsetup.sh 并把环境注入。"""
    if shutil.which("cjpm") is not None:
        return
    envsetup = Path("/opt/cangjie/envsetup.sh")
    if not envsetup.exists():
        raise SystemExit(
            "cjpm 不在 PATH 中且 /opt/cangjie/envsetup.sh 缺失；"
            "请按 README 安装仓颉 SDK 1.0.5。"
        )
    proc = subprocess.run(
        ["bash", "-c", f"source {envsetup} >/dev/null 2>&1 && env -0"],
        capture_output=True, check=True,
    )
    for chunk in proc.stdout.split(b"\x00"):
        if not chunk:
            continue
        key, _, value = chunk.decode("utf-8", errors="replace").partition("=")
        if key:
            os.environ[key] = value
    if shutil.which("cjpm") is None:
        raise SystemExit("source envsetup.sh 后仍找不到 cjpm — 请检查 SDK 安装。")


def find_cangjie_binary() -> Path:
    roots = [
        CANGJIE_DIR / "target" / "release" / "bin",
        CANGJIE_DIR / "target" / "debug" / "bin",
    ]
    for root in roots:
        for name in ("cangjie_bench", "main"):
            p = root / name
            if p.is_file() and os.access(p, os.X_OK):
                return p
    raise SystemExit("cangjie_bench 二进制未找到；检查 cjpm build 输出。")


def write_plan() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    plan = [{"file": f, "iterations": ITERATIONS[f]} for f in FIXTURE_ORDER]
    PLAN_PATH.write_text(json.dumps(plan, indent=2), encoding="utf-8")


def run_python_bench() -> None:
    log("python_xml.etree bench")
    out = OUT_DIR / "python.json"
    with out.open("w", encoding="utf-8") as fh:
        res = subprocess.run(
            [sys.executable, str(PYTHON_BENCH), str(FIXTURES_DIR), str(PLAN_PATH)],
            stdout=fh, text=True,
        )
    if res.returncode != 0:
        raise SystemExit(res.returncode)


def run_tinyxml2_bench() -> None:
    log("tinyxml2 bench")
    out = OUT_DIR / "tinyxml2.json"
    binary = TINYXML2_DIR / "bench"
    with out.open("w", encoding="utf-8") as fh:
        res = subprocess.run(
            [str(binary), str(FIXTURES_DIR), str(PLAN_PATH)],
            stdout=fh, text=True,
        )
    if res.returncode != 0:
        raise SystemExit(res.returncode)


def run_cangjie_bench() -> None:
    log("fastxml bench")
    out = OUT_DIR / "cangjie.json"
    binary = find_cangjie_binary()
    # 大 fixture 需要更大的堆上限以避免 OOM；只是上限，不影响计时口径。
    env = os.environ.copy()
    env.setdefault("cjHeapSize", "4GB")
    with out.open("w", encoding="utf-8") as fh:
        res = subprocess.run(
            [str(binary), str(FIXTURES_DIR), str(PLAN_PATH)],
            stdout=fh, text=True, env=env,
        )
    if res.returncode != 0:
        raise SystemExit(res.returncode)


def main() -> int:
    ensure_cjpm_available()
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    log("1. 生成 fixtures")
    run([sys.executable, str(FIXTURES_DIR / "generate.py")])

    log("2. 构建 tinyxml2 bench")
    run(["make", "-C", str(TINYXML2_DIR)])

    log("3. 构建 cangjie bench")
    run(["cjpm", "build"], cwd=CANGJIE_DIR)

    log("4. 写 plan.json")
    write_plan()

    log("5. 跑三端探针")
    run_python_bench()
    run_tinyxml2_bench()
    run_cangjie_bench()

    print(f"[bench] 三份 JSON 已写入 {OUT_DIR}")
    print("[bench] 生成报告：python3 perf/report.py")
    return 0


if __name__ == "__main__":
    sys.exit(main())
