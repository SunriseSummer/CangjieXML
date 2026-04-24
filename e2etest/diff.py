#!/usr/bin/env python3
"""
对 python.json 和 cangjie.json 做结构化 diff。

两份指纹都是 `{ filename -> fingerprint }`。我们逐文件、逐元素对比，差异
按"第一条差异 + 少量上下文"打印，避免深嵌套场景里刷屏。
任何不一致返回非 0，shell 可直接用作 CI 门禁。
"""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any


def diff_element(py: dict, cj: dict, file_label: str) -> list[str]:
    errs: list[str] = []
    for key in ("path", "depth", "name", "text"):
        if py[key] != cj[key]:
            errs.append(
                f"[{file_label}] elements[{py.get('path')}].{key}: "
                f"python={py[key]!r} vs cangjie={cj[key]!r}"
            )
    if py["attrs"] != cj["attrs"]:
        errs.append(
            f"[{file_label}] elements[{py.get('path')}].attrs: "
            f"python={py['attrs']!r} vs cangjie={cj['attrs']!r}"
        )
    return errs


def diff_file(py: dict, cj: dict) -> list[str]:
    name = py.get("file", "<unknown>")
    errs: list[str] = []
    for key in ("file", "declaration_present", "root", "total_elements"):
        if py[key] != cj[key]:
            errs.append(f"[{name}] {key}: python={py[key]!r} vs cangjie={cj[key]!r}")
    if errs:
        return errs  # 元素长度都对不上就不用继续逐条对比
    for i, (a, b) in enumerate(zip(py["elements"], cj["elements"])):
        errs.extend(diff_element(a, b, name))
        if len(errs) >= 20:
            errs.append(f"[{name}] (truncated, more differences after element #{i})")
            break
    return errs


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: diff.py <python.json> <cangjie.json>", file=sys.stderr)
        return 2
    py_all = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    cj_all = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))

    py_keys = set(py_all.keys())
    cj_keys = set(cj_all.keys())
    if py_keys != cj_keys:
        print("[FAIL] fixture set mismatch:")
        print(f"  only in python: {sorted(py_keys - cj_keys)}")
        print(f"  only in cangjie: {sorted(cj_keys - py_keys)}")
        return 1

    total_errs: list[str] = []
    for name in sorted(py_keys):
        total_errs.extend(diff_file(py_all[name], cj_all[name]))

    if total_errs:
        print(f"[FAIL] {len(total_errs)} difference(s):")
        for e in total_errs:
            print(f"  - {e}")
        return 1

    print(f"[PASS] all {len(py_keys)} fixtures produce identical fingerprints")
    return 0


if __name__ == "__main__":
    sys.exit(main())
