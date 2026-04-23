package cangjie_xml.parser

import cangjie_xml.dom.*

/**
 * 把 `parseString` 植回 `XmlDocument`，保持 DESIGN §4 约定的公共入口形态，
 * 同时让 `dom` 包不依赖 `parser`（反向依赖）。
 */
extend XmlDocument {

    /**
     * 解析一段 XML 文本，返回新构造的 `XmlDocument`。
     *
     * 失败时抛出 `XmlParseException`（携带 `XmlError` 与 `SourcePos`）。
     */
    public static func parseString(xml: String): XmlDocument {
        parseString(xml, XmlParseOptions.default_())
    }

    /** 带选项的解析入口。 */
    public static func parseString(xml: String, options: XmlParseOptions): XmlDocument {
        let doc = XmlDocument()
        let p = XmlParser(xml, options, doc)
        p.parseDocument()
        doc
    }
}
