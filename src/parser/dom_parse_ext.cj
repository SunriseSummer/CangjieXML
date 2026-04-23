package cangjie_xml.parser

import cangjie_xml.dom.*

/**
 * 顶层解析函数——与 `XmlDocument.parseString` 等价，专供跨包调用使用。
 *
 * 背景：cjc 1.0.5 对"在 A 包里 `extend` B 包类型且不实现任何接口"的扩展，
 * 会要求调用方"至少导入该扩展的某个继承接口"；而我们这个扩展只是追加方法，
 * 没有任何接口——于是跨包调用 `XmlDocument.parseString` 会编译失败。
 * 顶层函数则没有这个限制，作为稳定的跨包入口。
 */
public func parseXml(xml: String): XmlDocument {
    parseXml(xml, XmlParseOptions.default_())
}

/** 带选项的顶层解析函数。 */
public func parseXml(xml: String, options: XmlParseOptions): XmlDocument {
    let doc = XmlDocument()
    let p = XmlParser(xml, options, doc)
    p.parseDocument()
    doc
}

/**
 * 把 `parseString` 植回 `XmlDocument`，保持 DESIGN §4 约定的公共入口形态，
 * 同时让 `dom` 包不依赖 `parser`（反向依赖）。
 *
 * 注意：受 cjc 1.0.5 的 extension 可见性限制，跨包使用推荐 `parseXml(...)`。
 */
extend XmlDocument {

    /**
     * 解析一段 XML 文本，返回新构造的 `XmlDocument`。
     *
     * 失败时抛出 `XmlParseException`（携带 `XmlError` 与 `SourcePos`）。
     */
    public static func parseString(xml: String): XmlDocument {
        parseXml(xml)
    }

    /** 带选项的解析入口。 */
    public static func parseString(xml: String, options: XmlParseOptions): XmlDocument {
        parseXml(xml, options)
    }
}
