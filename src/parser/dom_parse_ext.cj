package tinyxml2.parser

import tinyxml2.dom.*

/**
 * 顶层解析函数——与 `XmlDocument.parseString` 等价，专供跨包调用使用。
 *
 * `parser` 包里通过 `extend XmlDocument` 添加的 `parseString` 方法不实现接口，
 * 跨包调用 cjc 1.0.5 不可见；本顶层函数作为稳定的跨包入口。
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
 * 把 `parseString` 植回 `XmlDocument`，保持公共入口形态，同时让 `dom` 包
 * 不依赖 `parser`。跨包使用推荐 `parseXml(...)`。
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
