package fastxml.parser

/**
 * XML 空白处理策略
 *
 * - `Preserve`：保留原文本空白
 * - `Collapse`：把连续空白序列折叠为单个空格，并删除纯空白文本节点
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

// 默认的最大元素嵌套深度
public const DEFAULT_MAX_ELEMENT_DEPTH: Int64 = 500

/**
 * XML 解析选项。不可变 struct，鼓励按调用点构造，避免跨调用共享可变状态
 *
 * - `whitespace`：文本节点的空白处理策略
 * - `maxElementDepth`：元素嵌套上限，超限抛 `ElementDepthExceeded`
 * - `acceptBom`：允许输入以 UTF-8 BOM 起始并自动剥离；关闭时遇到 BOM 报错
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

    // 使用全部默认值。便于 `parseString(xml)` 这类无选项调用
    public static func default_(): XmlParseOptions {
        XmlParseOptions()
    }
}
