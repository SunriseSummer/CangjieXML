#!/usr/bin/env python3
"""
生成 perf 基准测试所需的语料文件。

设计目标：
- 三档规模：small / medium / large，覆盖单次解析从微秒到百毫秒级的耗时谱，
  避免某一档过快导致计时噪声、或过慢导致跑一次基准动辄几分钟。
- 三种"典型"形态，对应实际工程中最常见的 XML 用法：
  * `catalog` —— 目录/条目/属性/文本（最常见的"DOM 业务文档"）。
  * `config`  —— 属性密集型（典型配置文件，几乎无文本节点）。
  * `deep`    —— 深嵌套（递归路径 / 栈深度），覆盖另一种极端结构。
- 输出固定为 UTF-8、带 XML 声明、紧凑（无多余空白）。三端解析所见字节一致，
  确保三方比较公平：差异完全由"库本身的实现"产生。

注意：故意避开"美化缩进 / 注释 / DOCTYPE / 处理指令"等非典型旁路，
e2e 已经覆盖功能正确性；perf 只关注最常用主路径的吞吐与时延。
"""
from __future__ import annotations

import sys
from pathlib import Path
from xml.sax.saxutils import escape

FIXTURE_DIR = Path(__file__).resolve().parent

# 各场景三档规模——单位是"条目数 / 嵌套层数"，落到字节数大致：
#   catalog small  ~ 6 KB，medium ~ 600 KB，large ~ 6 MB
#   config  small  ~ 4 KB，medium ~ 400 KB，large ~ 4 MB
#   deep    small  ~ 1 KB，medium ~ 30 KB，large ~ 300 KB（深度 1000 以避栈溢出）
SIZES = {
    "small":  {"catalog": 100,    "config": 100,    "deep": 50},
    "medium": {"catalog": 5000,   "config": 5000,   "deep": 200},
    # deep "large" 故意保持在 400——CangjieXML parser 默认 `maxElementDepth=500`，
    # 把 deep 推到 ~1000 会撞默认上限；在 perf 里我们想测"主路径"，不是去触发
    # 安全阈值，因此把上限定在 400 既给三端足够压力，又留出余量。
    "large":  {"catalog": 30000,  "config": 30000,  "deep": 400},
}


def gen_catalog(n: int) -> str:
    """书目目录：n 条 <book>，每条带两个属性 + 4 个文本子元素。"""
    parts = ['<?xml version="1.0" encoding="UTF-8"?>', '<bookstore>']
    for i in range(1, n + 1):
        title = escape(f"Title {i} - Foundations of Computing")
        author = escape(f"Author {i % 97}")
        year = 1950 + (i % 75)
        price = f"{(i % 1000) / 10:.2f}"
        parts.append(
            f'<book id="{i}" category="cs">'
            f'<title>{title}</title>'
            f'<author>{author}</author>'
            f'<year>{year}</year>'
            f'<price currency="USD">{price}</price>'
            f'</book>'
        )
    parts.append('</bookstore>')
    return ''.join(parts)


def gen_config(n: int) -> str:
    """配置：n 个 <feature>，全部以属性承载键值对——属性查询性能。"""
    parts = ['<?xml version="1.0" encoding="UTF-8"?>',
             '<config version="2" env="prod">',
             '<server host="127.0.0.1" port="8080">',
             '<tls enabled="true" cert="/etc/srv.pem"/>',
             '</server>',
             '<features>']
    for i in range(n):
        parts.append(
            f'<feature name="feat-{i}" on="{"true" if i % 2 == 0 else "false"}" '
            f'priority="{i % 10}" group="g{i % 16}"/>'
        )
    parts.append('</features></config>')
    return ''.join(parts)


def gen_deep(depth: int) -> str:
    """深嵌套：单链 depth 层。"""
    parts = ['<?xml version="1.0" encoding="UTF-8"?>']
    parts.extend(f'<l{i} i="{i}">' for i in range(depth))
    parts.append('leaf')
    parts.extend(f'</l{i}>' for i in reversed(range(depth)))
    return ''.join(parts)


GENERATORS = {
    "catalog": gen_catalog,
    "config":  gen_config,
    "deep":    gen_deep,
}


def main() -> int:
    FIXTURE_DIR.mkdir(parents=True, exist_ok=True)
    for size, kinds in SIZES.items():
        for kind, param in kinds.items():
            text = GENERATORS[kind](param)
            path = FIXTURE_DIR / f"{kind}_{size}.xml"
            path.write_text(text, encoding="utf-8")
            print(f"[fixtures] {path.name} - {len(text):,} bytes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
