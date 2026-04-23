/*
 * parser — ParserOptions
 *
 * 对应 libxml2: `xmlParserOption` 位掩码（`XML_PARSE_*`）。
 *
 * 差异：
 *   - 结构体 + 命名参数 + 默认值（`DESIGN.md §7.5`）。调用点自解释，不会出现
 *     `opts | XML_PARSE_RECOVER | XML_PARSE_NOENT | ...` 的难读位运算。
 *   - 安全优先：`loadExternal = false`，`maxDepth` / `maxEntityExpansion` 预置保守值。
 */
package cangjie_xml.parser

import cangjie_xml.core.*

public const DEFAULT_MAX_DEPTH: Int64 = 256
public const DEFAULT_MAX_ENTITY_EXPANSION: Int64 = 10_000_000

public struct ParserOptions {
    /** XML 版本（决定字符合法域 + 换行归一）。 */
    public let version: XmlVersion
    /** `true` 时把预定义 / 用户实体展开为字符并并入 `Characters` 事件；
     *  `false` 时透传为 `SaxEvent.EntityReference`。 */
    public let substituteEntities: Bool
    /** `true` 时容错模式（Phase 3c 完整实现）；本迭代仅用于 API 稳定。 */
    public let recover: Bool
    /** 保留元素间空白文本；`false` 时解析器跳过"仅空白"的 Characters 事件。 */
    public let keepBlanks: Bool
    /** 允许加载外部实体（Phase 3c 接入）。当前迭代被忽略，等同 false。 */
    public let loadExternal: Bool
    /** 最大元素嵌套深度；超过抛 `LimitExceeded`。 */
    public let maxDepth: Int64
    /** 实体展开总字符上限（Billion Laughs 防护）。 */
    public let maxEntityExpansion: Int64
    /** 可选的 intern 池；传入后元素 / 属性 QName 的本地名会走此池。 */
    public let nameTable: ?NameTable
    /** 可选的自定义实体解析器；默认 `DefaultEntityResolver`（仅预定义实体）。 */
    public let entityResolver: ?EntityResolver

    public init(
        version!: XmlVersion = XmlVersion.V10,
        substituteEntities!: Bool = true,
        recover!: Bool = false,
        keepBlanks!: Bool = true,
        loadExternal!: Bool = false,
        maxDepth!: Int64 = DEFAULT_MAX_DEPTH,
        maxEntityExpansion!: Int64 = DEFAULT_MAX_ENTITY_EXPANSION,
        nameTable!: ?NameTable = None,
        entityResolver!: ?EntityResolver = None
    ) {
        this.version = version
        this.substituteEntities = substituteEntities
        this.recover = recover
        this.keepBlanks = keepBlanks
        this.loadExternal = loadExternal
        this.maxDepth = maxDepth
        this.maxEntityExpansion = maxEntityExpansion
        this.nameTable = nameTable
        this.entityResolver = entityResolver
    }

    /** 等价于 `ParserOptions()`，供调用点语义清晰。 */
    public static func defaults(): ParserOptions {
        return ParserOptions()
    }
}
