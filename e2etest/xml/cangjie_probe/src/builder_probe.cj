package cangjie_probe

import std.collection.*
import tinyxml2.dom.*
import tinyxml2.build.*
import tinyxml2.parser.*
import tinyxml2.writer.*

/**
 * Builder 端到端测试：在仓颉侧用 `XmlDocumentBuilder` **构造**一棵与
 * `01_bookstore.xml` 结构等价的文档 → write → 再 parse → 生成同一份指纹。
 *
 * 通过与 Python 对原 fixture 的指纹严格相等来验证两点：
 * 1. Builder → DOM → Writer 的语义链路正确；
 * 2. 属性顺序 / 文本 / 元素层级在 build 路径上的默认行为与 parse 路径一致。
 *
 * 为保持 diff 形状统一，本函数吐出 `{ "01_bookstore.xml": {...} }` 这样的 JSON，
 * 直接与 Python 侧 `python.json` 按文件名键共用 diff 管线。
 */
func renderBuilderFixtures(): String {
    let doc = buildBookstoreEquivalent()
    // 走一遍 write → parse，确保 writer 参与到覆盖路径里。
    let sink = StringXmlSink()
    XmlWriter(sink, options: XmlWriteOptions.compactPreset()).writeDocument(doc)
    let rebuilt = parseXml(sink.toString())

    let elements = ArrayList<ElementRecord>()
    match (rebuilt.rootElement) {
        case Some(root) => visitElement(root, "", 0, 0, elements)
        case None => ()
    }
    let rootName = match (rebuilt.rootElement) {
        case Some(r) => r.name
        case None => ""
    }

    let json = StringBuilder()
    json.append("{\n")
    // 文件名保持与 Python 侧 01_bookstore.xml 一致，让 diff.py 按键对齐。
    emitFingerprint(json, "01_bookstore.xml", true, rootName, elements)
    json.append("\n}\n")
    json.toString()
}

/**
 * 与 `fixtures/generate.py::build_bookstore` 一一对应。
 *
 * 任何一侧改动都必须同步另一侧——这一"双写"的代价换来了"builder 能否准确复现
 * ET 的默认写出形态"的强回归信号。
 */
func buildBookstoreEquivalent(): XmlDocument {
    let books: Array<(String, String, String, String)> = [
        ("SICP",            "Abelson & Sussman", "1996", "49.99"),
        ("TAOCP vol.1",     "Knuth",             "1997", "89.00"),
        ("The Dragon Book", "Aho et al.",        "2006", "75.50"),
    ]
    let builder = XmlDocumentBuilder().declaration()
    builder.root("bookstore") { r =>
        var i = 1
        for ((title, author, year, price) in books) {
            let idStr = "${i}"
            r.element("book") { b =>
                b.attribute("id", idStr).attribute("category", "cs")
                b.element("title")  { t => t.text(title).build() }
                b.element("author") { a => a.text(author).build() }
                b.element("year")   { y => y.text(year).build() }
                b.element("price")  { p =>
                    p.attribute("currency", "USD").text(price).build()
                }
            }
            i++
        }
    }
    builder.build()
}

/** 与主 `emitFingerprint` 冲突的 wrapper 已内联；本文件只保留构造与渲染。 */
