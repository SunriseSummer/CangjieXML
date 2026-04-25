#!/usr/bin/env python3
"""
Python 端 perf 探针——基于标准库 `xml.etree.ElementTree`。

四个典型场景（与 cangjie / tinyxml2 端一一对应）：
  1. parse        从字节解析为 DOM
  2. serialize    把 DOM 序列化为字节（`ET.tostring`）
  3. roundtrip    parse → serialize 回环
  4. traverse     DOM 上递归遍历，统计元素与属性总数（"读端"典型负载）

输出 JSON 到 stdout，结构：
  { "library": "python_xml.etree",
    "results": [
      { "scenario": str, "fixture": str, "iterations": int,
        "elapsed_ms_total": float, "elapsed_ms_avg": float,
        "bytes": int }, ... ] }

迭代数由 run.py 根据规模决定，本脚本只忠实计时。
计时使用 `time.perf_counter_ns`——单调高分辨率，最小化系统时钟扰动。
"""
from __future__ import annotations

import json
import sys
import time
import xml.etree.ElementTree as ET
from pathlib import Path

# Python `xml.etree` 的 `_serialize_xml` 是递归实现，深嵌套 fixture（深度 1000）
# 会撞默认 1000 的递归限。这里拉到 5000——纯 Python 栈帧不大，机器栈足够；
# 同时这个调整不影响任何耗时数据：递归深度只决定能否完成，不会污染计时。
sys.setrecursionlimit(5000)


def parse_bytes(raw: bytes) -> ET.ElementTree:
    """ET 没有直接接 bytes 的 API；fromstring 接 bytes 也接 str。"""
    return ET.ElementTree(ET.fromstring(raw))


def serialize(tree: ET.ElementTree) -> bytes:
    return ET.tostring(tree.getroot(), encoding="utf-8", xml_declaration=True)


def traverse(tree: ET.ElementTree) -> int:
    """统计元素数量 + 属性数量——既访问树拓扑也访问属性表，
    避免被 JIT/编译器优化为空循环。"""
    total = 0
    for elem in tree.getroot().iter():
        total += 1 + len(elem.attrib)
    return total


def time_ms(fn, iterations: int) -> float:
    """重复 fn iterations 次，返回总耗时毫秒。"""
    start = time.perf_counter_ns()
    for _ in range(iterations):
        fn()
    end = time.perf_counter_ns()
    return (end - start) / 1_000_000.0


def bench_one(path: Path, iterations: int) -> list[dict]:
    raw = path.read_bytes()
    size = len(raw)
    # 预解析一次给 serialize/traverse 用——这两个场景应只测自身耗时，不重复 parse。
    pre_tree = parse_bytes(raw)

    out: list[dict] = []

    parse_total = time_ms(lambda: parse_bytes(raw), iterations)
    out.append(_record("parse", path.name, iterations, parse_total, size))

    ser_total = time_ms(lambda: serialize(pre_tree), iterations)
    out.append(_record("serialize", path.name, iterations, ser_total, size))

    rt_total = time_ms(lambda: serialize(parse_bytes(raw)), iterations)
    out.append(_record("roundtrip", path.name, iterations, rt_total, size))

    trv_total = time_ms(lambda: traverse(pre_tree), iterations)
    out.append(_record("traverse", path.name, iterations, trv_total, size))

    return out


def _record(scenario: str, fixture: str, iterations: int,
            total_ms: float, size: int) -> dict:
    return {
        "scenario":         scenario,
        "fixture":          fixture,
        "iterations":       iterations,
        "elapsed_ms_total": round(total_ms, 4),
        "elapsed_ms_avg":   round(total_ms / iterations, 6),
        "bytes":            size,
    }


def main(argv: list[str]) -> int:
    # 用法：bench.py <fixture_dir> <plan.json>
    # plan.json 形如 [{"file":"catalog_small.xml","iterations":1000}, ...]
    if len(argv) != 3:
        print("usage: bench.py <fixture_dir> <plan.json>", file=sys.stderr)
        return 2
    fixture_dir = Path(argv[1])
    plan = json.loads(Path(argv[2]).read_text(encoding="utf-8"))

    results: list[dict] = []
    for entry in plan:
        path = fixture_dir / entry["file"]
        results.extend(bench_one(path, entry["iterations"]))

    json.dump({"library": "python_xml.etree", "results": results},
              sys.stdout, ensure_ascii=False, indent=2)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
