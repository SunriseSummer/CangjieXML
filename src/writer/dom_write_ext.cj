package cangjie_xml.writer

import cangjie_xml.dom.*

/**
 * 为 `XmlDocument` 与 `XmlElement` 增补 `writeToString(options:)` 便捷 API。
 *
 * DESIGN §6.2 把 `writeToString` 列为 `XmlDocument` 的公共方法。为避免 DOM 包
 * 依赖 Writer 包（打破 DESIGN §4 的分层方向），此处使用扩展声明：Writer 依赖
 * DOM，然后通过 `extend` 把该方法植回 DOM 类型。
 *
 * ## 为什么需要 `XmlWritable` 接口
 *
 * cjc 1.0.5 规则：跨包 `extend T { ... }` 的 `public` 方法，外部调用方只能通过
 * 接口声明的签名访问——未出现在接口里的方法即使是 `public` 也"跨包不可见"。
 * 这与 `query.XmlQueryable` 是同一个坑：若不列在接口里，用户 `import
 * cangjie_xml.writer.*` 后写 `doc.writeToString(...)` 会编译失败。
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
public interface XmlWritable {
    func writeToString(): String
    func writeToString(options: XmlWriteOptions): String
}

extend XmlDocument <: XmlWritable {
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

extend XmlElement <: XmlWritable {
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
