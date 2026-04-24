/*
 * writer — XmlWriter：推式 XML 构造器
 *
 * 对应 libxml2: `xmlwriter.c` 的 `xmlNewTextWriter*` 族与 `xmlTextWriterStart*` /
 * `xmlTextWriterEnd*` 接口。
 *
 * 设计差异（参见 DESIGN §7.6）：
 *   - 所有方法对调用顺序做**显式状态机校验**：根元素唯一、起止标签匹配、
 *     `writeAttribute` 只能紧跟 `startElement`、XML 声明只能在首次输出前。
 *     发现不变量违反立即抛 `XmlException`，并把实例转为 `faulted` 状态，
 *     之后所有写入都会拒绝（与 libxml2 把错误状态静默化的做法不同）。
 *   - 不内置编码转换；UTF-8 字节直接写入传入的 `IoSink`。需要 GBK / UTF-16
 *     时在上层用 `EncodingSink` 包一层 sink。
 *   - 缩进逻辑与 `save.DocumentSerializer` 一致："叶子文本"元素（只含 Text /
 *     CDATA）保持同行避免污染字符数据。
 *
 * 典型用法：
 * ```
 * let sink = MemorySink()
 * let w = XmlWriter(sink, opts: WriterOptions.pretty())
 * w.writeXmlDeclaration(version: "1.0", encoding: Some("UTF-8"))
 * w.startElement(QName.of("root"))
 *   w.writeAttribute(QName.of("id"), "1")
 *   w.writeText("hello")
 * w.endElement()
 * w.close()
 * let bytes = sink.toBytes()
 * ```
 *
 * 实现分布：
 *   - 本文件：字段、构造、公开入口、状态枚举。
 *   - `xml_writer_tags.cj`：标签 / 属性 / 文本 / CDATA / PI / Comment / 缩进。
 *
 * Cangjie 约束：主类体不能调用自身 extend 成员，沿用项目内"主类 + 包级桥接"
 * 模式（见 parser / save 子包）。
 */
package cangjie_xml.writer

import cangjie_xml.core.*
import cangjie_xml.io.*

/* ---------- 写入器状态机 ---------- */

/**
 * 状态机位置。`Start` 表示尚未写入任何内容；`Prolog` 表示已写过声明 / Comment /
 * PI，但根元素未开始；`InElementOpen` 表示处于 start-tag 构造中（允许属性）；
 * `InElementContent` 表示 start-tag 已关闭，可以写子节点；`Epilog` 表示根元素
 * 已收尾，只允许再写 Comment / PI；`Closed` 表示 `close()` 已被调用；
 * `Faulted` 表示写入过程中曾抛错，后续任何写入都拒绝。
 */
enum WriterState <: Equatable<WriterState> {
    | Start
    | Prolog
    | InElementOpen
    | InElementContent
    | Epilog
    | Closed
    | Faulted

    public operator func ==(that: WriterState): Bool {
        match ((this, that)) {
            case (Start, Start) => true
            case (Prolog, Prolog) => true
            case (InElementOpen, InElementOpen) => true
            case (InElementContent, InElementContent) => true
            case (Epilog, Epilog) => true
            case (Closed, Closed) => true
            case (Faulted, Faulted) => true
            case _ => false
        }
    }

    public operator func !=(that: WriterState): Bool {
        return !(this == that)
    }
}

/* ---------- 栈帧：每个 open 元素一条 ---------- */

struct ElementFrame {
    public let lexicalName: String
    /** `true` 表示本帧在 content 阶段目前只看到 Text / CDATA；影响 endElement
     *  的缩进策略（保持同行）。开始写任何 Element / Comment / PI 会将其置 false。 */
    public var leafTextOnly: Bool
    /** `true` 表示本帧从 startElement 到 endElement 之间没有写任何子节点，
     *  可自闭合为 `<a/>`。 */
    public var hasAnyChild: Bool

    public init(lexicalName: String) {
        this.lexicalName = lexicalName
        this.leafTextOnly = true
        this.hasAnyChild = false
    }
}

/* ---------- 主类 ---------- */

public class XmlWriter {
    let sink: IoSink
    let opts: WriterOptions
    var state: WriterState
    let stack: ElementStack

    public init(sink: IoSink, opts!: WriterOptions = WriterOptions()) {
        this.sink = sink
        this.opts = opts
        this.state = WriterState.Start
        this.stack = ElementStack()
    }

    /* ---------- 当前栈帧深度 ---------- */
    public func depth(): Int64 {
        return stack.size()
    }

    /** 是否处于错误状态；`true` 后任何写入会抛错。 */
    public func isFaulted(): Bool {
        return state == WriterState.Faulted
    }

    public func isClosed(): Bool {
        return state == WriterState.Closed
    }

    /* ---------- 公开入口（委派给 extend） ---------- */

    public func writeXmlDeclaration(
        version!: String = "1.0",
        encoding!: ?String = None,
        standalone!: Standalone3 = Standalone3.Unspecified
    ): Unit {
        writerWriteXmlDeclaration(this, version, encoding, standalone)
    }

    public func writeDoctype(name: String): Unit {
        writerWriteDoctype(this, name)
    }

    public func startElement(qname: QName): Unit {
        writerStartElement(this, qname.lexical())
    }

    public func startElement(localName: String): Unit {
        writerStartElement(this, localName)
    }

    public func writeAttribute(qname: QName, value: String): Unit {
        writerWriteAttribute(this, qname.lexical(), value)
    }

    public func writeAttribute(name: String, value: String): Unit {
        writerWriteAttribute(this, name, value)
    }

    /** 便捷写法：输出 `xmlns="uri"` 或 `xmlns:prefix="uri"`。 */
    public func writeNamespace(prefix: ?String, uri: String): Unit {
        let name = match (prefix) {
            case Some(p) where p.size > 0 => "xmlns:${p}"
            case _ => "xmlns"
        }
        writerWriteAttribute(this, name, uri)
    }

    public func endElement(): Unit {
        writerEndElement(this)
    }

    public func writeText(data: String): Unit {
        writerWriteText(this, data)
    }

    public func writeCdata(data: String): Unit {
        writerWriteCdata(this, data)
    }

    public func writeComment(data: String): Unit {
        writerWriteComment(this, data)
    }

    public func writePi(target: String, data!: ?String = None): Unit {
        writerWritePi(this, target, data)
    }

    /** 直通写入字节；跳过所有转义。调用方自行负责良构性。
     *  仅允许在 `InElementContent` / `Prolog` / `Epilog` / `Start` 状态下使用。 */
    public func writeRawBytes(bytes: Array<Byte>): Unit {
        writerWriteRawBytes(this, bytes)
    }

    /**
     * 关闭写入器：
     *   - 若仍有 open 元素未闭合，转 `Faulted` 并抛错；
     *   - flush 底层 sink；
     *   - 设为 `Closed`；之后任何写入都会抛错。
     * 注意：**不会**关闭底层 `IoSink`——sink 所有权由调用方保留，便于拿快照。
     */
    public func close(): Unit {
        writerClose(this)
    }
}

/* ---------- Standalone 三态（与 parser.Standalone 解耦） ---------- */

/** `XmlWriter` 的三态 standalone 参数；与 `parser.Standalone` 同构，不直接依赖
 *  parser 子包，避免反向依赖。 */
public enum Standalone3 <: Equatable<Standalone3> {
    | Yes
    | No
    | Unspecified

    public operator func ==(that: Standalone3): Bool {
        match ((this, that)) {
            case (Yes, Yes) => true
            case (No, No) => true
            case (Unspecified, Unspecified) => true
            case _ => false
        }
    }

    public operator func !=(that: Standalone3): Bool {
        return !(this == that)
    }
}

/* ---------- 包级桥接：由 extend 实现 ---------- */

func writerWriteXmlDeclaration(w: XmlWriter, v: String, e: ?String, s: Standalone3): Unit {
    w.runWriteXmlDeclaration(v, e, s)
}
func writerWriteDoctype(w: XmlWriter, n: String): Unit { w.runWriteDoctype(n) }
func writerStartElement(w: XmlWriter, n: String): Unit { w.runStartElement(n) }
func writerWriteAttribute(w: XmlWriter, n: String, v: String): Unit { w.runWriteAttribute(n, v) }
func writerEndElement(w: XmlWriter): Unit { w.runEndElement() }
func writerWriteText(w: XmlWriter, d: String): Unit { w.runWriteText(d) }
func writerWriteCdata(w: XmlWriter, d: String): Unit { w.runWriteCdata(d) }
func writerWriteComment(w: XmlWriter, d: String): Unit { w.runWriteComment(d) }
func writerWritePi(w: XmlWriter, t: String, d: ?String): Unit { w.runWritePi(t, d) }
func writerWriteRawBytes(w: XmlWriter, b: Array<Byte>): Unit { w.runWriteRawBytes(b) }
func writerClose(w: XmlWriter): Unit { w.runClose() }
