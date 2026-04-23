package cangjie_xml.parser

/**
 * XML 空白处理策略。
 *
 * 对应 tinyxml2 的 `PRESERVE_WHITESPACE` / `COLLAPSE_WHITESPACE`。
 * 合并模式会把任何连续空白序列折叠为单个空格，常见于"只关心语义值"的场景。
 *
 * `Pedantic` 暂不实现——tinyxml2 中它与 `Preserve` 行为差异极小，推迟到
 * 日后如有用户需求再补。
 */
public enum XmlWhitespaceMode <: ToString {
    | Preserve
    | Collapse

    public func toString(): String {
        match (this) {
            case Preserve => "Preserve"
            case Collapse => "Collapse"
        }
    }
}

/** 默认的最大元素嵌套深度，与 tinyxml2 的 `TIXML2_MAX_ELEMENT_DEPTH` 对齐。 */
public const DEFAULT_MAX_ELEMENT_DEPTH: Int64 = 500

/**
 * XML 解析选项。不可变 struct，鼓励按调用点构造，避免跨调用共享可变状态。
 *
 * - `whitespace`：文本节点的空白处理策略。
 * - `maxElementDepth`：元素嵌套上限，超限抛 `ElementDepthExceeded`。
 * - `acceptBom`：允许输入以 UTF-8 BOM 起始并自动剥离；关闭时遇到 BOM 报错。
 */
public struct XmlParseOptions {
    public let whitespace: XmlWhitespaceMode
    public let maxElementDepth: Int64
    public let acceptBom: Bool

    public init(
        whitespace!: XmlWhitespaceMode = Preserve,
        maxElementDepth!: Int64 = DEFAULT_MAX_ELEMENT_DEPTH,
        acceptBom!: Bool = true
    ) {
        this.whitespace = whitespace
        this.maxElementDepth = maxElementDepth
        this.acceptBom = acceptBom
    }

    /** 使用全部默认值。便于 `parseString(xml)` 这类无选项调用。 */
    public static func default_(): XmlParseOptions {
        XmlParseOptions()
    }
}
