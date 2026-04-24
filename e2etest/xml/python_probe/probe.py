#!/usr/bin/env python3
"""
对每个 fixture 提取一份"指纹"JSON，格式与仓颉侧 probe 严格一致。

指纹形状：

    {
      "file": "<basename>",
      "declaration_present": bool,
      "root": "<tag>",
      "total_elements": int,
      "elements": [
        {"path": "root/child[0]/leaf[1]", "depth": 1, "name": "leaf",
         "attrs": {"k": "v", ...},   # 以属性名字典序
         "text": "normalized direct text"}
      ]
    }

"direct text" = **仅该元素自己的直接文本**（不含子元素内部文本），两端 strip、
内部空白折叠成单空格。这样既规避各解析器对"空白只在子元素间"的处理差异，
又保留真正有内容的文本差异信号。

CDATA 在 ET 里呈现为普通文本段，在我们 CangjieXML 侧也一样可以取回文本，
所以两端直接按文本比较即可。
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Any


WS_RUN = re.compile(r"\s+")


def normalize_text(s: str | None) -> str:
    if not s:
        return ""
    return WS_RUN.sub(" ", s).strip()


def has_xml_declaration(path: Path) -> bool:
    with path.open("rb") as f:
        head = f.read(64)
    # BOM 可能在前面；容忍之
    if head.startswith(b"\xef\xbb\xbf"):
        head = head[3:]
    return head.lstrip().startswith(b"<?xml")


def element_direct_text(el: ET.Element) -> str:
    """ET 里"直接文本" = el.text + 每个子元素的 .tail 拼接。"""
    parts: list[str] = []
    if el.text:
        parts.append(el.text)
    for child in el:
        if child.tail:
            parts.append(child.tail)
    return normalize_text("".join(parts))


def visit(el: ET.Element, parent_path: str, depth: int, sibling_index: int,
          out: list[dict[str, Any]]) -> None:
    path = f"{parent_path}/{el.tag}[{sibling_index}]" if parent_path else f"{el.tag}[{sibling_index}]"
    out.append({
        "path": path,
        "depth": depth,
        "name": el.tag,
        "attrs": {k: el.attrib[k] for k in sorted(el.attrib.keys())},
        "text": element_direct_text(el),
    })
    # 给每个孩子按"同名同父兄弟序号"编号——与仓颉侧一致
    name_counters: dict[str, int] = {}
    for child in el:
        idx = name_counters.get(child.tag, 0)
        name_counters[child.tag] = idx + 1
        visit(child, path, depth + 1, idx, out)


def fingerprint(path: Path) -> dict[str, Any]:
    tree = ET.parse(path)
    root = tree.getroot()
    elements: list[dict[str, Any]] = []
    visit(root, "", 0, 0, elements)
    return {
        "file": path.name,
        "declaration_present": has_xml_declaration(path),
        "root": root.tag,
        "total_elements": len(elements),
        "elements": elements,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("fixtures_dir")
    parser.add_argument("out_path")
    args = parser.parse_args()

    fixtures = sorted(Path(args.fixtures_dir).glob("*.xml"))
    report = {f.name: fingerprint(f) for f in fixtures}
    Path(args.out_path).write_text(
        json.dumps(report, indent=2, ensure_ascii=False, sort_keys=False),
        encoding="utf-8",
    )
    print(f"[python_probe] wrote {args.out_path} ({len(report)} files)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
