#!/usr/bin/env python3
"""
生成 e2e 所需的一组典型 XML 样例，使用 Python 标准库 xml.etree.ElementTree 写出。

把样例生成单独放到 Python 端（而不是直接手写 XML 字符串）的理由：
1. 让"正确的 XML"由 Python 的 ET 保证——后续仓颉侧解析如果匹配不上，锅一定在我们。
2. ET 的 tostring 输出能覆盖大多数真实工程里见到的写法：单 / 双引号属性、
   自闭合 / 非自闭合、嵌套子树、CDATA（通过 ET.CDATA，Python 3.8+）、注释、
   声明头、UTF-8 含非 ASCII 字符等。
3. 一份 XML 一个 `.xml` 文件，便于 probe 两端独立驱动、按文件 diff。
"""

from __future__ import annotations

import os
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

FIXTURE_DIR = Path(__file__).resolve().parent


def _write(tree: ET.ElementTree, name: str, *, declaration: bool = True) -> None:
    path = FIXTURE_DIR / name
    tree.write(
        path,
        encoding="utf-8",
        xml_declaration=declaration,
        short_empty_elements=True,
    )


def build_bookstore() -> ET.ElementTree:
    """最典型的"目录 + 条目 + 属性 + 文本"场景——最小可用 XML。"""
    root = ET.Element("bookstore")
    for i, (title, author, year, price) in enumerate(
        [
            ("SICP", "Abelson & Sussman", "1996", "49.99"),
            ("TAOCP vol.1", "Knuth", "1997", "89.00"),
            ("The Dragon Book", "Aho et al.", "2006", "75.50"),
        ],
        start=1,
    ):
        book = ET.SubElement(root, "book", {"id": str(i), "category": "cs"})
        ET.SubElement(book, "title").text = title
        ET.SubElement(book, "author").text = author
        ET.SubElement(book, "year").text = year
        ET.SubElement(book, "price", {"currency": "USD"}).text = price
    return ET.ElementTree(root)


def build_config() -> ET.ElementTree:
    """典型的配置文件——属性密集型，几乎没有文本。"""
    root = ET.Element("config", {"version": "2", "env": "prod"})
    srv = ET.SubElement(root, "server", {"host": "127.0.0.1", "port": "8080"})
    ET.SubElement(srv, "tls", {"enabled": "true", "cert": "/etc/srv.pem"})
    db = ET.SubElement(root, "database", {"driver": "postgres"})
    ET.SubElement(db, "pool", {"min": "4", "max": "32", "timeoutMs": "5000"})
    features = ET.SubElement(root, "features")
    for name in ("search", "export", "audit"):
        ET.SubElement(features, "feature", {"name": name, "on": "true"})
    return ET.ElementTree(root)


def build_deep() -> ET.ElementTree:
    """深嵌套——覆盖解析器的递归路径与我们的 maxElementDepth 策略。"""
    depth = 40
    root = ET.Element("l0")
    cur = root
    for i in range(1, depth + 1):
        cur = ET.SubElement(cur, f"l{i}", {"i": str(i)})
    cur.text = "leaf"
    return ET.ElementTree(root)


def build_unicode() -> ET.ElementTree:
    """UTF-8：属性值与文本里混入中文 / 重音 / emoji。元素名保持 ASCII，以
    绕开我们当前 parser 对 name-start-char 的 ASCII 限制（这个限制本身是
    DESIGN 中明列的取舍，不属于 e2e 要覆盖的偏差）。"""
    root = ET.Element("library")
    book = ET.SubElement(root, "book", {"lang": "zh", "title": "算法导论"})
    ET.SubElement(book, "author").text = "Cormen 等"
    ET.SubElement(book, "note").text = "排序与查找 — Gödel 🔍"
    return ET.ElementTree(root)


def build_cdata_and_escapes() -> ET.ElementTree:
    """CDATA + 五个 XML 预定义实体的往返。
    
    ET 没有稳定的 CDATA 写出 API（CDATA 提案从未落地标准库），所以我们只用
    ET 生成"纯文本走实体转义"的部分；带真正 CDATA 节点的文件由
    `write_cdata_fixture` 以手写字节的方式单独写出——这部分 ET 也能正常读回，
    CDATA 对 ET 而言本就只是一种语法等价的文本段。
    """
    root = ET.Element("snippets")
    plain = ET.SubElement(root, "plain")
    # 触发 < > & ' " 五个实体的写出路径
    plain.text = "a<b & c>d 'e' \"f\""
    return ET.ElementTree(root)


def write_cdata_fixture(path: Path) -> None:
    """手写一份含 CDATA 区段的文件——ET 读回后 .text 会是 CDATA 里的原文。"""
    xml = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<snippets>'
        '<code lang="x"><![CDATA[if (x < y && y > 0) return "ok";]]></code>'
        '<mixed>before <![CDATA[<raw & stuff>]]> after</mixed>'
        '</snippets>'
    )
    path.write_text(xml, encoding="utf-8")


def build_mixed_content() -> ET.ElementTree:
    """混合内容：文本与子元素在同一个父节点下交替。ET 用 .text / .tail 表达。"""
    root = ET.Element("doc")
    p = ET.SubElement(root, "p")
    p.text = "Hello "
    b = ET.SubElement(p, "b")
    b.text = "bold"
    b.tail = " world, and "
    i = ET.SubElement(p, "i")
    i.text = "italic"
    i.tail = "."
    return ET.ElementTree(root)


def build_empty_and_selfclosing() -> ET.ElementTree:
    """空元素 / 自闭合 / 仅属性。"""
    root = ET.Element("root")
    ET.SubElement(root, "empty")
    ET.SubElement(root, "attrs-only", {"a": "1", "b": "2"})
    ET.SubElement(root, "nested").append(ET.Element("inner"))
    return ET.ElementTree(root)


def build_rss() -> ET.ElementTree:
    """RSS 风格——命名空间暂不处理，这里用普通 tag 模拟结构。"""
    root = ET.Element("rss", {"version": "2.0"})
    ch = ET.SubElement(root, "channel")
    ET.SubElement(ch, "title").text = "CangjieXML blog"
    ET.SubElement(ch, "link").text = "https://example.invalid/feed"
    for i in range(3):
        item = ET.SubElement(ch, "item")
        ET.SubElement(item, "title").text = f"Post {i}"
        ET.SubElement(item, "guid", {"isPermaLink": "false"}).text = f"post-{i}"
        ET.SubElement(item, "description").text = f"Content of post {i}."
    return ET.ElementTree(root)


FIXTURES = {
    "01_bookstore.xml": build_bookstore,
    "02_config.xml": build_config,
    "03_deep.xml": build_deep,
    "04_unicode.xml": build_unicode,
    "05_cdata_and_escapes.xml": build_cdata_and_escapes,
    "06_mixed_content.xml": build_mixed_content,
    "07_empty_and_selfclosing.xml": build_empty_and_selfclosing,
    "08_rss.xml": build_rss,
}


# ---- 手写 XML 片段（ET 无法表达的结构） ---------------------------------

def write_cdata_terminator_fixture(path: Path) -> None:
    """CDATA 内部含 `]]>`——触发 writer 分段路径；Python ET 与我们都应正常读回。"""
    xml = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<r><code><![CDATA[foo]]]]><![CDATA[>bar]]></code></r>'
    )
    path.write_text(xml, encoding="utf-8")


def write_bom_fixture(path: Path) -> None:
    """UTF-8 BOM 开头——对齐 `acceptBom` 默认路径；Python ET 会自动忽略 BOM。"""
    xml = '<?xml version="1.0" encoding="utf-8"?>\n<r><x a="1">hi</x></r>'
    path.write_bytes(b"\xef\xbb\xbf" + xml.encode("utf-8"))


def write_doctype_fixture(path: Path) -> None:
    """DOCTYPE 走 XmlUnknown 路径；ET 会忽略 DOCTYPE，剩余元素对齐即可。"""
    xml = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<!DOCTYPE note SYSTEM "note.dtd">\n'
        '<note><to>Tove</to><from>Jani</from><body>Don\'t forget me!</body></note>'
    )
    path.write_text(xml, encoding="utf-8")


def write_pi_in_element_fixture(path: Path) -> None:
    """元素内处理指令——我们存为 XmlUnknown("?...?")；ET 默认忽略 PI。"""
    xml = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<doc><?xml-stylesheet href="x.xsl" type="text/xsl"?>'
        '<p>hello</p></doc>'
    )
    path.write_text(xml, encoding="utf-8")


def write_entity_refs_fixture(path: Path) -> None:
    """集中触发命名 / 十进制 / 十六进制实体——与 04_unicode 互补。"""
    xml = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<refs>'
        '<named>&amp;&lt;&gt;&quot;&apos;</named>'
        '<decimal>A=&#65; Z=&#90;</decimal>'
        '<hex>zh=&#x4E2D;&#x6587; emoji=&#x1F600;</hex>'
        '</refs>'
    )
    path.write_text(xml, encoding="utf-8")


def main() -> int:
    FIXTURE_DIR.mkdir(parents=True, exist_ok=True)
    for name, factory in FIXTURES.items():
        tree = factory()
        _write(tree, name, declaration=True)
        print(f"[fixtures] wrote {name}")
    # 一份无 XML 声明的变体，用于覆盖 "acceptBom + 无 declaration" 路径
    tree = build_bookstore()
    _write(tree, "09_bookstore_no_decl.xml", declaration=False)
    print("[fixtures] wrote 09_bookstore_no_decl.xml")
    # 真正含 CDATA 区段的文件（手写，ET 不支持写 CDATA）
    write_cdata_fixture(FIXTURE_DIR / "10_cdata.xml")
    print("[fixtures] wrote 10_cdata.xml")
    # 覆盖面扩展：CDATA `]]>` 分段 / BOM / DOCTYPE / 元素内 PI / 实体集合
    write_cdata_terminator_fixture(FIXTURE_DIR / "11_cdata_terminator.xml")
    print("[fixtures] wrote 11_cdata_terminator.xml")
    write_bom_fixture(FIXTURE_DIR / "12_bom.xml")
    print("[fixtures] wrote 12_bom.xml")
    write_doctype_fixture(FIXTURE_DIR / "13_doctype.xml")
    print("[fixtures] wrote 13_doctype.xml")
    write_pi_in_element_fixture(FIXTURE_DIR / "14_pi_in_element.xml")
    print("[fixtures] wrote 14_pi_in_element.xml")
    write_entity_refs_fixture(FIXTURE_DIR / "15_entity_refs.xml")
    print("[fixtures] wrote 15_entity_refs.xml")
    return 0


if __name__ == "__main__":
    sys.exit(main())
