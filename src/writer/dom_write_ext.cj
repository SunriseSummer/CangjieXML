package fastxml.writer

import fastxml.dom.*

/**
 * 为 `XmlDocument` 与 `XmlElement` 增补 `writeToString(options:)` 便捷 API。
 *
 * 该接口提供"DOM 类型上直接写出"的入口：DOM 包不依赖 Writer 包，Writer 包
 * 通过 `extend ... <: XmlWritable` 把方法植回 DOM 类型；接口声明保证了跨包
 * 可见性。
 *
 * ```cangjie
 * import fastxml.dom.*
 * import fastxml.writer.*
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
