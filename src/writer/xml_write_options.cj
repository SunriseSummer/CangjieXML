package cangjie_xml.writer

/**
 * XML 写出选项。
 *
 * 不可变值类型（`struct` + `let`），一经构造不可修改——保证"相同 DOM +
 * 相同 options → 完全相同输出"的确定性。
 *
 * | 字段 | 语义 | 默认 |
 * |---|---|---|
 * | `compact` | `true` 时紧凑输出（无缩进、无行终止）；`false` 时美化输出 | `false` |
 * | `indent` | `compact = false` 时每层嵌套使用的缩进串 | `"    "`（4 空格） |
 * | `lineEnd` | 行结束符；`compact = true` 时该字段无效 | `"\n"` |
 * | `writeDeclaration` | 是否输出 `<?xml ... ?>` 声明。`true` 时：若文档已有声明则原样输出，否则输出默认声明；`false` 时：不输出任何声明 | `true` |
 * | `writeBom` | 是否在输出开头写入 UTF-8 BOM（`EF BB BF`）。若文档 `writeBom=true` 可在此处强制关闭 | `false` |
 * | `boolTrueText` / `boolFalseText` | Query / Builder 层写出 `Bool` 属性时使用的字面量 | `"true"` / `"false"` |
 */
public struct XmlWriteOptions {
    public let compact: Bool
    public let indent: String
    public let lineEnd: String
    public let writeDeclaration: Bool
    public let writeBom: Bool
    public let boolTrueText: String
    public let boolFalseText: String

    public init(
        compact!: Bool = false,
        indent!: String = "    ",
        lineEnd!: String = "\n",
        writeDeclaration!: Bool = true,
        writeBom!: Bool = false,
        boolTrueText!: String = "true",
        boolFalseText!: String = "false"
    ) {
        this.compact = compact
        this.indent = indent
        this.lineEnd = lineEnd
        this.writeDeclaration = writeDeclaration
        this.writeBom = writeBom
        this.boolTrueText = boolTrueText
        this.boolFalseText = boolFalseText
    }

    /** 默认配置：美化输出，写声明，不写 BOM。 */
    public static func default_(): XmlWriteOptions {
        XmlWriteOptions()
    }

    /** 紧凑配置：单行无缩进；文档声明仍输出。 */
    public static func compactPreset(): XmlWriteOptions {
        XmlWriteOptions(compact: true, lineEnd: "")
    }
}
