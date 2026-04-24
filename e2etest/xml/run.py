#!/usr/bin/env python3
"""
e2etest/xml 入口脚本——替代原先的 `run.sh`（项目规范禁止 sh 脚本，全部用 Python）。

流程：
  1. `python3 fixtures/generate.py`                 —— 生成 10 份 `.xml`
  2. `cjpm build` （在 `cangjie_probe/` 下）        —— 构建仓颉 probe
  3. `python_probe/probe.py`                         —— Python 端指纹 → `out/python.json`
  4. `cangjie_probe` 以多种模式分别跑 → 多份 cangjie 指纹 JSON
  5. `diff.py` 逐模式对比 Python 指纹

仓颉工具链通过 `/opt/cangjie/envsetup.sh` 自动加载——若 `cjpm` 已在 PATH 里
（例如 CI 中已经 source 过），本脚本不会重复 source。

任何一步失败立即以非 0 退出，便于当 CI 门禁。
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
FIXTURES_DIR = SCRIPT_DIR / "fixtures"
PYTHON_PROBE = SCRIPT_DIR / "python_probe" / "probe.py"
CANGJIE_PROBE_DIR = SCRIPT_DIR / "cangjie_probe"
DIFF_PY = SCRIPT_DIR / "diff.py"
OUT_DIR = SCRIPT_DIR / "out"


def log(section: str) -> None:
    print(f"=== {section}")


def run(cmd: list[str], *, cwd: Path | None = None, env: dict[str, str] | None = None) -> None:
    """Run *cmd*；失败直接抛异常并以非 0 退出。"""
    display = " ".join(cmd)
    where = f" (cwd={cwd})" if cwd is not None else ""
    print(f"$ {display}{where}")
    result = subprocess.run(cmd, cwd=cwd, env=env)
    if result.returncode != 0:
        raise SystemExit(result.returncode)


def ensure_cjpm_available() -> None:
    """若 `cjpm` 不在 PATH，尝试 source `/opt/cangjie/envsetup.sh` 并把
    其中导出的环境变量拷贝到当前进程——这样子进程调用 `cjpm` / `cjc`
    时就能找到。

    仅在命令缺失时才会执行；若用户已经在 shell 里 source 过，本步骤跳过。
    """
    if shutil.which("cjpm") is not None:
        return
    envsetup = Path("/opt/cangjie/envsetup.sh")
    if not envsetup.exists():
        raise SystemExit(
            "cjpm not found in PATH and /opt/cangjie/envsetup.sh is missing; "
            "请先安装仓颉 SDK 或手动 source envsetup.sh 后再运行。"
        )
    # 在一次 bash 调用里 source 并打印环境变量，然后解析回 os.environ。
    proc = subprocess.run(
        ["bash", "-c", f"source {envsetup} >/dev/null 2>&1 && env -0"],
        capture_output=True,
        check=True,
    )
    for chunk in proc.stdout.split(b"\x00"):
        if not chunk:
            continue
        try:
            key, _, value = chunk.decode("utf-8").partition("=")
        except UnicodeDecodeError:
            continue
        if key:
            os.environ[key] = value
    if shutil.which("cjpm") is None:
        raise SystemExit("sourced envsetup.sh but cjpm still missing — 请检查 SDK 安装。")


def find_probe_binary() -> Path:
    """cjpm 的产物命名会在不同版本里变化——有时是 package 名，有时是 `main`。
    此处同时认这两种常见名字。"""
    search_roots = [
        CANGJIE_PROBE_DIR / "target" / "release" / "bin",
        CANGJIE_PROBE_DIR / "target" / "debug" / "bin",
    ]
    candidate_names = ("cangjie_probe", "main")
    for root in search_roots:
        for name in candidate_names:
            p = root / name
            if p.is_file() and os.access(p, os.X_OK):
                return p
    # 兜底：在 target 下全量搜索。跳过日志/缓存目录。
    for candidate in (CANGJIE_PROBE_DIR / "target").rglob("*"):
        if candidate.is_file() and os.access(candidate, os.X_OK) \
                and candidate.name in candidate_names:
            return candidate
    raise SystemExit("cangjie_probe 构建产物未找到；请检查 cjpm build 是否成功。")


def main() -> int:
    ensure_cjpm_available()

    OUT_DIR.mkdir(parents=True, exist_ok=True)

    log("1. 生成 fixtures")
    run([sys.executable, str(FIXTURES_DIR / "generate.py")])

    log("2. 构建仓颉 probe")
    run(["cjpm", "build"], cwd=CANGJIE_PROBE_DIR)
    probe_bin = find_probe_binary()

    log("3. Python 端指纹")
    python_json = OUT_DIR / "python.json"
    run([sys.executable, str(PYTHON_PROBE), str(FIXTURES_DIR), str(python_json)])

    log("4. 仓颉端指纹（多模式）")
    modes = [
        ("parse", OUT_DIR / "cangjie.json"),
        ("roundtrip-pretty", OUT_DIR / "cangjie_roundtrip_pretty.json"),
        ("roundtrip-compact", OUT_DIR / "cangjie_roundtrip_compact.json"),
        ("bytes", OUT_DIR / "cangjie_bytes.json"),
        ("builder", OUT_DIR / "cangjie_builder.json"),
    ]
    for mode, out_json in modes:
        run([str(probe_bin), mode, str(FIXTURES_DIR), str(out_json)])

    log("5. 对比")
    # `builder` 模式只覆盖 01_bookstore.xml 一份 fixture，因此放宽为 --subset。
    for mode, out_json in modes:
        extra = ["--subset"] if mode == "builder" else []
        run([sys.executable, str(DIFF_PY), str(python_json), str(out_json),
             "--label", mode, *extra])

    print("[PASS] e2e/xml 全部模式指纹一致")
    return 0


if __name__ == "__main__":
    sys.exit(main())
