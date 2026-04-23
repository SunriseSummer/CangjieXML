package cangjie_xml.writer

import cangjie_xml.dom.*

/**
 * 为 `XmlDocument` 与 `XmlElement` 增补 `writeToString(options:)` 便捷 API。
 *
 * DESIGN §6.2 把 `writeToString` 列为 `XmlDocument` 的公共方法。为避免 DOM 包
 * 依赖 Writer 包（打破 DESIGN §4 的分层方向），此处使用扩展声明：Writer 依赖
 * DOM，然后通过 `extend` 把该方法植回 DOM 类型。
 *
 * ## 用法
 *
 * ```cangjie
 * import cangjie_xml.dom.*
 * import cangjie_xml.writer.*
 *
 * let doc = XmlDocument()
 * // ...
 * let xml = doc.writeToString()                                 // 默认美化
 * let c   = doc.writeToString(XmlWriteOptions.compactPreset())  // 紧凑
 * ```
 *
 * `XmlElement.writeToString()` 产出不含声明 / BOM 的纯元素子树。
 */

extend XmlDocument {
    public func writeToString(): String {
        writeToString(XmlWriteOptions.default_())
    }

    public func writeToString(options: XmlWriteOptions): String {
        let sink = StringXmlSink()
        let w = XmlWriter(sink, options: options)
        w.writeDocument(this)
        sink.toString()
    }
}

extend XmlElement {
    public func writeToString(): String {
        writeToString(XmlWriteOptions.default_())
    }

    public func writeToString(options: XmlWriteOptions): String {
        let sink = StringXmlSink()
        let w = XmlWriter(sink, options: options)
        w.writeElement(this)
        sink.toString()
    }
}
