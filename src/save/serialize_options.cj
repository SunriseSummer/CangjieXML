/*
 * save — SerializeOptions：序列化选项
 *
 * 对应 libxml2: `xmlsave.c` 中 `xmlSaveCtxt` 的 `options` / `indent` / `encoding`
 * 等字段。CangjieXML 用不可变 `struct` + 命名参数默认值（见 `DESIGN.md §7.5`），
 * 调用点自解释。
 *
 * 选项范围严格限定本阶段（Phase 5a 基础序列化器）：
 *   - 不做编码转换（始终输出 UTF-8 文本；上层需要 GBK/UTF-16 走 encoding 包
 *     的 `EncodingSink`）；
 *   - 不做命名空间"最小化"（如 libxml2 `XML_SAVE_NO_EMPTY` / `XML_SAVE_NO_DECL`
 *     的某些组合），仅直写 `Attr.isNamespaceDeclaration = true` 的声明；
 *   - 不暴露底层 Writer 钩子（Phase 5b 引入 `XmlWriter` / `IoSink` 后开放）。
 */
package cangjie_xml.save

public struct SerializeOptions {
    /** `true` 时跳过 `<?xml ... ?>` 声明行。默认 `false`（保留或合成声明）。 */
    public let omitXmlDeclaration: Bool
    /** `true` 时在元素间换行并按嵌套深度插入 `indentString`。默认 `false`（与输入逐字节对齐）。 */
    public let indent: Bool
    /** 缩进单元。仅当 `indent = true` 时生效。 */
    public let indentString: String
    /** 行终止符。仅当 `indent = true` 时用于换行；默认 `"\n"`（平台无关）。 */
    public let lineSeparator: String
    /** `true` 时把 `CdataSection` 以普通文本 + 转义输出（丢失 CDATA 语义但字节更短）。 */
    public let cdataAsText: Bool
    /**
     * `true` 时遇到 XML 声明的 `position` 为 `unknown`（即解析器合成出来，非源自原文档）时
     * 跳过声明输出。默认 `true`——避免给无声明的源文档"无中生有"地写入声明。
     * 与 `omitXmlDeclaration` 的区别：`omitXmlDeclaration` 强制跳过，本选项只跳过合成的。
     */
    public let omitSyntheticXmlDeclaration: Bool

    public init(
        omitXmlDeclaration!: Bool = false,
        indent!: Bool = false,
        indentString!: String = "  ",
        lineSeparator!: String = "\n",
        cdataAsText!: Bool = false,
        omitSyntheticXmlDeclaration!: Bool = true
    ) {
        this.omitXmlDeclaration = omitXmlDeclaration
        this.indent = indent
        this.indentString = indentString
        this.lineSeparator = lineSeparator
        this.cdataAsText = cdataAsText
        this.omitSyntheticXmlDeclaration = omitSyntheticXmlDeclaration
    }

    /** `SerializeOptions()`，供调用点语义清晰。 */
    public static func defaults(): SerializeOptions {
        return SerializeOptions()
    }

    /** 常见"pretty print"预设：开启缩进 + 保留源 XML 声明。 */
    public static func pretty(): SerializeOptions {
        return SerializeOptions(indent: true)
    }
}
