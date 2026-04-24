/*
 * reader — XmlReader：拉式游标
 *
 * 对应 libxml2 `xmlTextReader` / .NET `XmlReader`。在 `XmlParser` 产出的
 * `Iterator<SaxEvent>` 之上提供一个"游标"：调用方 `read()` 前进一步，然后
 * 查询 `nodeType` / `localName` / `value` / ... 得到当前节点的属性。
 *
 * 相较直接消费 SaxEvent，XmlReader 的价值：
 *   - 用一个"光标"隐藏事件流与属性数组的差异，属性作为"虚拟节点"暴露；
 *   - 支持 `skip()` —— 一次性读到当前元素的 EndElement；
 *   - 检测空元素（StartElement 立刻跟 EndElement 且位置相同）并暴露
 *     `isEmptyElement`；
 *   - 支持 pull-based 深层嵌套而不爆栈（parser 本身是 lazy iterator）。
 *
 * 设计要点：
 *   - **单一预读 buffer**：内部保存"下一个 SaxEvent"用于空元素检测，不做
 *     任意回放；足够覆盖 isEmptyElement 的决策。
 *   - **属性游标是虚拟的**：`moveToAttribute` / `moveToNextAttribute` 切换内部
 *     `attrCursor` 字段，`nodeType` 暂时报 `Attribute`，但并不消费 SaxEvent；
 *     `moveToElement` 回到宿主 Element。
 *   - **Whitespace 识别**：prolog / epilog / 元素间的 `Characters` 若全为
 *     XML 空白字符（SP/HT/CR/LF），暴露为 `ReaderNodeType.Whitespace`，内部
 *     仍然一个 SaxEvent 对应一个 read()。
 *   - **错误路径**：`ParseError` 事件 → 立刻抛 `XmlException`，状态置 `Error`。
 *
 * 不在本迭代范围：
 *   - `readInnerXml` / `readOuterXml`（需要序列化器联动，留待 Phase 4c+）；
 *   - `readElementContentAs*` 强类型读取；
 *   - `moveToAttributeNs`（`moveToAttribute(localName, uri)` 已覆盖）；
 *   - `readSubtree`（返回子 reader，需要独立迭代器适配）。
 */
package cangjie_xml.reader

import cangjie_xml.core.*
import cangjie_xml.parser.*

public class XmlReader {
    let parser: XmlParser
    var state: ReaderState
    /** 当前光标对应的事件；Initial 时为 None。 */
    var current: ?SaxEvent
    /** 预读一位，用于 isEmptyElement 检测 + Whitespace 识别延迟判定。 */
    var peeked: ?SaxEvent
    /** 当前元素是否是 `<a/>` 形态。`current` 不是 Element 时恒 false。 */
    var emptyElement: Bool
    /** 元素嵌套深度；StartElement → +1，EndElement → -1（在 read 前）。
     *  Element 节点上报告的 depth 为当前元素深度（含自身，从 0 开始计）。 */
    var depthVal: Int64
    /** 光标停在 Attribute 时的属性索引；-1 表示停在宿主 Element 本身。 */
    var attrCursor: Int64

    init(parser: XmlParser) {
        this.parser = parser
        this.state = ReaderState.Initial
        this.current = None
        this.peeked = None
        this.emptyElement = false
        this.depthVal = -1
        this.attrCursor = -1
    }

    /* ---------- 静态构造 ---------- */

    public static func fromString(s: String, opts!: ParserOptions = ParserOptions()): XmlReader {
        return XmlReader(XmlParser.fromString(s, opts: opts))
    }

    public static func fromParser(p: XmlParser): XmlReader {
        return XmlReader(p)
    }

    /* ---------- 状态查询 ---------- */

    public func readerState(): ReaderState { return state }
    public func isClosed(): Bool { return state == ReaderState.Closed }
    public func isEof(): Bool { return state == ReaderState.EndOfFile }
    public func depth(): Int64 { return depthVal }
    public func isEmptyElement(): Bool { return emptyElement }

    public func nodeType(): ReaderNodeType {
        if (attrCursor >= 0) {
            return ReaderNodeType.Attribute
        }
        match (current) {
            case None => return ReaderNodeType.None
            case Some(e) => return classifyEvent(e)
        }
    }

    public func position(): Position {
        if (attrCursor >= 0) {
            // 属性节点用属性自己的位置
            match (current) {
                case Some(StartElement(_, _, attrs, _)) where attrCursor < attrs.size =>
                    return attrs[attrCursor].position
                case _ => ()
            }
        }
        match (current) {
            case Some(e) => return e.position()
            case None => return Position.unknown()
        }
    }

    /* ---------- 名字 / 值 ---------- */

    /** 本地名；若不适用则返回空串。 */
    public func localName(): String { return readerLocalName(this) }

    /** 前缀；若无则返回空串。 */
    public func prefix(): String { return readerPrefix(this) }

    /** 命名空间 URI；若无则返回空串。 */
    public func namespaceUri(): String { return readerNamespaceUri(this) }

    /** `prefix:localName` 形式的完整名；若无前缀则等于 `localName`。 */
    public func name(): String { return readerName(this) }

    /** 有语义的 value：Text/Cdata/Comment/Whitespace → 文本内容；Pi → data；
     *  XmlDeclaration → version 字符串；Attribute → 属性值；EntityReference → 实体名；
     *  其它 → 空串。 */
    public func value(): String { return readerValue(this) }

    public func hasValue(): Bool {
        match (nodeType()) {
            case Text | Cdata | Comment | Whitespace | Pi | Attribute | EntityReference | XmlDeclaration => return true
            case _ => return false
        }
    }

    /* ---------- 属性 ---------- */

    public func hasAttributes(): Bool {
        return attributeCount() > 0
    }

    public func attributeCount(): Int64 {
        match (current) {
            case Some(StartElement(_, _, attrs, _)) => return attrs.size
            case _ => return 0
        }
    }

    /** 跳到第 i 个属性；越界返回 false 且不移动。 */
    public func moveToAttribute(i: Int64): Bool {
        let n = attributeCount()
        if (i < 0 || i >= n) {
            return false
        }
        attrCursor = i
        return true
    }

    /** 按名字找属性。uri=None 时只比较 localName；否则两者都比较。 */
    public func moveToAttribute(localName: String, uri!: ?String = None): Bool {
        match (current) {
            case Some(StartElement(_, _, attrs, _)) =>
                var i = 0
                while (i < attrs.size) {
                    let a = attrs[i].qname
                    let ok = a.localName == localName && match ((uri, a.uri)) {
                        case (None, _) => true
                        case (Some(u), Some(au)) => u == au
                        case (Some(_), None) => false
                    }
                    if (ok) {
                        attrCursor = i
                        return true
                    }
                    i += 1
                }
                return false
            case _ => return false
        }
    }

    public func moveToFirstAttribute(): Bool {
        return moveToAttribute(0)
    }

    public func moveToNextAttribute(): Bool {
        let n = attributeCount()
        if (n == 0) {
            return false
        }
        if (attrCursor < 0) {
            attrCursor = 0
            return true
        }
        if (attrCursor + 1 >= n) {
            return false
        }
        attrCursor += 1
        return true
    }

    /** 把属性游标回到宿主 Element。 */
    public func moveToElement(): Bool {
        if (attrCursor < 0) {
            return false
        }
        attrCursor = -1
        return true
    }

    /* ---------- 前进 ---------- */

    public func read(): Bool { return readerRead(this) }

    /** 若光标停在 Element 上，跳过其全部子孙，停在对应 EndElement（或对于空元素，
     *  停在同一 Element 上不动）。停在其它节点：直接 `read()` 一次。 */
    public func skip(): Bool { return readerSkip(this) }

    public func close(): Unit {
        state = ReaderState.Closed
    }

    /* ---------- 内部：把 SaxEvent 映射到 ReaderNodeType ---------- */

    func classifyEvent(e: SaxEvent): ReaderNodeType {
        match (e) {
            case StartDocument(_) => return ReaderNodeType.XmlDeclaration
            case EndDocument(_) => return ReaderNodeType.EndDocument
            case StartElement(_, _, _, _) => return ReaderNodeType.Element
            case EndElement(_, _) => return ReaderNodeType.EndElement
            case Characters(_, s) =>
                if (isAllXmlSpace(s)) {
                    return ReaderNodeType.Whitespace
                }
                return ReaderNodeType.Text
            case Cdata(_, _) => return ReaderNodeType.Cdata
            case CommentEvent(_, _) => return ReaderNodeType.Comment
            case Pi(_, _, _) => return ReaderNodeType.Pi
            case Doctype(_, _) => return ReaderNodeType.Doctype
            case EntityReference(_, _) => return ReaderNodeType.EntityReference
            case ParseError(_) => return ReaderNodeType.None
        }
    }
}

/* ---------- 辅助：XML 1.0 定义的 S 空白字符 (#x20 | #x9 | #xD | #xA) ---------- */

func isAllXmlSpace(s: String): Bool {
    if (s.size == 0) {
        return false
    }
    for (r in s.runes()) {
        let c = UInt32(r)
        if (c != 0x20 && c != 0x09 && c != 0x0D && c != 0x0A) {
            return false
        }
    }
    return true
}

/* ---------- 包级桥接（主类不能调用自身 extend 成员） ---------- */

func readerRead(r: XmlReader): Bool { return r.runRead() }
func readerSkip(r: XmlReader): Bool { return r.runSkip() }
func readerLocalName(r: XmlReader): String { return r.runLocalName() }
func readerPrefix(r: XmlReader): String { return r.runPrefix() }
func readerNamespaceUri(r: XmlReader): String { return r.runNamespaceUri() }
func readerName(r: XmlReader): String { return r.runName() }
func readerValue(r: XmlReader): String { return r.runValue() }
