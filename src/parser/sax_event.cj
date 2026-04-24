/*
 * parser — SAX 事件流数据模型
 *
 * 对应 libxml2: `SAX2.c` 中的回调参数结构 + `parser.h` 的内部事件概念。
 *
 * 设计差异（参见 `DESIGN.md §7.2`）：
 *   - 不用 C 风格回调 / void* 用户上下文，改为单一 `enum SaxEvent`。
 *   - 用 `Iterator<SaxEvent>` 暴露，惰性求值；push / pull / tree 三种消费姿势
 *     共用同一份事件流，消除了 libxml2 推拉双实现的行为偏差风险。
 *   - 属性、命名空间、XML 声明通过 **不可变结构体**（`Attribute` / `NsContext` /
 *     `XmlDecl`）语义化携带，不再复用"前缀拼接字符串"。
 */
package cangjie_xml.parser

import cangjie_xml.core.*

/* ------------------------------------------------------------------ */
/*  XmlDecl：`<?xml version="..." encoding="..." standalone="..."?>`   */
/* ------------------------------------------------------------------ */

/** Standalone 三态。`None` 表示 XML 声明中未出现 standalone 属性。 */
public enum Standalone <: Equatable<Standalone> & ToString {
    | Yes
    | No
    | Unspecified

    public operator func ==(that: Standalone): Bool {
        match ((this, that)) {
            case (Yes, Yes) => return true
            case (No, No) => return true
            case (Unspecified, Unspecified) => return true
            case _ => return false
        }
    }

    public operator func !=(that: Standalone): Bool {
        return !(this == that)
    }

    public func toString(): String {
        match (this) {
            case Yes => return "yes"
            case No => return "no"
            case Unspecified => return "<unspecified>"
        }
    }
}

/**
 * XML 声明。
 *
 * - `version` 默认 `"1.0"`；若文档无 XML 声明，解析器仍会合成一个默认声明。
 * - `encoding` 为 `None` 表示 XML 声明未指定（解析器自身仍可能通过 BOM / 启发式
 *   推断出编码；要获取该值请查 `DecodingSource.detectedEncoding`）。
 * - `standalone` 保留 W3C 原始三态。
 */
public struct XmlDecl <: ToString {
    public let version: String
    public let encoding: ?String
    public let standalone: Standalone
    public let position: Position
    /**
     * `true` 表示本声明由 parser 在缺失 `<?xml ...?>` 时合成，并非源自原文档。
     * 序列化器据此实现 "无声明的源不被无中生有地写入声明" 的默认语义。
     */
    public let isSynthetic: Bool

    public init(
        version!: String = "1.0",
        encoding!: ?String = None,
        standalone!: Standalone = Standalone.Unspecified,
        position!: Position = Position.unknown(),
        isSynthetic!: Bool = false
    ) {
        this.version = version
        this.encoding = encoding
        this.standalone = standalone
        this.position = position
        this.isSynthetic = isSynthetic
    }

    public func toString(): String {
        let enc = match (encoding) {
            case Some(e) => " encoding=\"${e}\""
            case None => ""
        }
        let sa = match (standalone) {
            case Unspecified => ""
            case Yes => " standalone=\"yes\""
            case No => " standalone=\"no\""
        }
        return "<?xml version=\"${version}\"${enc}${sa}?>"
    }
}

/* ------------------------------------------------------------------ */
/*  Attribute：解析后的属性                                             */
/* ------------------------------------------------------------------ */

/**
 * 单个属性。
 *
 * - `qname` 携带已解析的 `(localName, prefix, uri)`：未声明前缀会在 parser 层
 *   报错（`NamespaceError`）；默认命名空间**不**应用到属性（W3C Namespaces §6.2）。
 * - `value` 为**完全展开后**的字符串：预定义实体已展开，字符引用已解析，
 *   §3.3.3 属性值归一化已完成（TAB/LF → SPACE，由词法器完成）。
 * - `isNamespaceDeclaration` 便于上层快速识别 `xmlns` / `xmlns:prefix` 属性。
 *   这些属性仍然会作为 `Attribute` 出现，但通常上层不需要作为普通属性处理。
 * - `position` 指向属性名起点。
 */
public struct Attribute <: ToString {
    public let qname: QName
    public let value: String
    public let position: Position
    public let isNamespaceDeclaration: Bool

    public init(
        qname: QName,
        value: String,
        position!: Position = Position.unknown(),
        isNamespaceDeclaration!: Bool = false
    ) {
        this.qname = qname
        this.value = value
        this.position = position
        this.isNamespaceDeclaration = isNamespaceDeclaration
    }

    public func toString(): String {
        return "${qname.lexical()}=\"${value}\""
    }
}

/* ------------------------------------------------------------------ */
/*  SaxEvent                                                           */
/* ------------------------------------------------------------------ */

/**
 * SAX 事件。每个事件携带发生位置。
 *
 * 事件顺序约束（非容错模式下）：
 *   StartDocument
 *   [ Doctype? ]
 *   [ Comment | Pi | Characters(仅空白)]*
 *   StartElement (根)
 *     { StartElement | EndElement | Characters | Cdata | Comment | Pi
 *       | EntityReference }*
 *   EndElement (根)
 *   [ Comment | Pi | Characters(仅空白)]*
 *   EndDocument
 *
 * 在容错模式（`recover = true`，Phase 3c）下可能出现 `ParseError` 事件，但
 * 事件流仍会尽力保持上述骨架。
 */
public enum SaxEvent <: ToString {
    | StartDocument(XmlDecl)
    | EndDocument(Position)
    | StartElement(Position, QName, Array<Attribute>, NsContext)
    | EndElement(Position, QName)
    | Characters(Position, String)
    | Cdata(Position, String)
    | CommentEvent(Position, String)
    | Pi(Position, String, String)
    | Doctype(Position, String)
    /** 已展开的命名实体 / 字符引用在 `substituteEntities=true`（默认）下不会出现这个事件；
     *  `substituteEntities=false` 则透传实体引用名供下游自行处理。 */
    | EntityReference(Position, String)
    | ParseError(XmlError)

    /** 取事件位置；`ParseError` 取其 `XmlError.position()`。 */
    public func position(): Position {
        match (this) {
            case StartDocument(d) => return d.position
            case EndDocument(p) => return p
            case StartElement(p, _, _, _) => return p
            case EndElement(p, _) => return p
            case Characters(p, _) => return p
            case Cdata(p, _) => return p
            case CommentEvent(p, _) => return p
            case Pi(p, _, _) => return p
            case Doctype(p, _) => return p
            case EntityReference(p, _) => return p
            case ParseError(e) => return e.position()
        }
    }

    public func toString(): String {
        match (this) {
            case StartDocument(d) => return "StartDocument(${d})"
            case EndDocument(_) => return "EndDocument"
            case StartElement(_, n, attrs, _) => return "StartElement(${n.lexical()}, ${attrs.size} attrs)"
            case EndElement(_, n) => return "EndElement(${n.lexical()})"
            case Characters(_, s) => return "Characters(${s.size} chars)"
            case Cdata(_, s) => return "Cdata(${s.size} chars)"
            case CommentEvent(_, _) => return "Comment"
            case Pi(_, t, _) => return "Pi(${t})"
            case Doctype(_, n) => return "Doctype(${n})"
            case EntityReference(_, n) => return "EntityReference(${n})"
            case ParseError(e) => return "ParseError(${e})"
        }
    }
}
