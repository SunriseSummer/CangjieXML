/*
 * writer — WriterOptions：推式写入选项
 *
 * 对应 libxml2: `xmlwriter.c` 的 `xmlTextWriterCtxt` 中 `indent`, `indent_str`
 * 等字段。与 `save.SerializeOptions` 刻意保持一致命名，便于二者互换使用。
 *
 * 说明：编码转换不在 `WriterOptions` 里表达 —— 上层应当把 `EncodingSink`
 * 作为 `XmlWriter` 的 sink 传入，`XmlWriter` 只吐 UTF-8 字节。
 */
package cangjie_xml.writer

public struct WriterOptions {
    /** `true` 时 `XmlWriter` 不允许调用 `writeXmlDeclaration`（调用会抛错）。 */
    public let omitXmlDeclaration: Bool
    /** 缩进开关。与 `save.SerializeOptions.indent` 语义一致。 */
    public let indent: Bool
    /** 缩进单元，默认两空格。 */
    public let indentString: String
    /** 行分隔符；缩进模式下的换行符。 */
    public let lineSeparator: String

    public init(
        omitXmlDeclaration!: Bool = false,
        indent!: Bool = false,
        indentString!: String = "  ",
        lineSeparator!: String = "\n"
    ) {
        this.omitXmlDeclaration = omitXmlDeclaration
        this.indent = indent
        this.indentString = indentString
        this.lineSeparator = lineSeparator
    }

    public static func defaults(): WriterOptions {
        return WriterOptions()
    }

    public static func pretty(): WriterOptions {
        return WriterOptions(indent: true)
    }
}
