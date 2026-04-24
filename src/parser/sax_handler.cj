/*
 * parser — SaxHandler：推式回调接口 + 驱动器
 *
 * CangjieXML 的第三种事件消费方式。对标 libxml2 `xmlSAXHandler` / Java SAX2
 * `ContentHandler+ErrorHandler`：调用方实现 `SaxHandler` 的若干方法，driver
 * 遍历 parser 产出的 `Iterator<SaxEvent>` 并逐事件回调。
 *
 * 三种消费方式对比：
 *   - `XmlParser: Iterator<SaxEvent>` — 主动拉 + 模式匹配，最灵活；
 *   - `XmlReader`                     — 游标 + 字段查询，适合 skip/subtree；
 *   - `SaxHandler` + `SaxDriver`      — 被动回调，适合"一次性扫完整个文档 +
 *                                        只处理关心的几类节点"的 filter / 采集。
 *
 * 设计要点：
 *   - 使用 `interface + 默认 open class` 组合：`SaxHandler` 为纯接口
 *     （Cangjie 接口不可给默认体），`DefaultSaxHandler` 提供空实现，用户继承
 *     后按需覆写。
 *   - `parseError(err)` 回调返回 `Bool`：`true` = 继续遍历，`false` = driver
 *     立即停止（相当于早退）。默认实现把错误抛为 `XmlException` —— 匹配
 *     parser 在非容错模式下的既有行为。
 *   - driver 不自己 try-catch parser 的异常：parser 抛出的 `XmlException`
 *     直接透传；调用方选择怎么处理。
 *   - 不支持在 handler 内部重入 driver —— driver 只是线性分发器，handler
 *     要重入请自己用 `XmlParser` 重开。
 */
package cangjie_xml.parser

import cangjie_xml.core.*

/**
 * 推式 SAX 回调接口。每个事件对应一个方法。
 *
 * 所有方法的 `Position` 参数是事件发生位置（行列 / 偏移），与 `SaxEvent`
 * 一致。`characters` / `cdata` 的文本在非容错模式下已做属性值规范化 /
 * 换行规范化（由词法器完成）。
 *
 * 注意：
 *   - `startElement` 的 `attrs` 已经按出现顺序归一化；其中 `xmlns` 与
 *     `xmlns:prefix` 属性以 `isNamespaceDeclaration = true` 标记。
 *   - `ns` 是该元素看到的完整命名空间映射（继承 + 本级覆盖）。
 *   - `entityReference` 只在 parser 配置 `substituteEntities = false` 时
 *     触发（默认会展开并以 `characters` 回调）。
 */
public interface SaxHandler {
    func startDocument(decl: XmlDecl): Unit
    func endDocument(pos: Position): Unit
    func startElement(
        pos: Position,
        name: QName,
        attrs: Array<Attribute>,
        ns: NsContext
    ): Unit
    func endElement(pos: Position, name: QName): Unit
    func characters(pos: Position, text: String): Unit
    func cdata(pos: Position, text: String): Unit
    func comment(pos: Position, text: String): Unit
    func processingInstruction(pos: Position, target: String, data: String): Unit
    func doctype(pos: Position, name: String): Unit
    func entityReference(pos: Position, name: String): Unit
    /**
     * 当 parser 发出 `SaxEvent.ParseError` 时被回调。
     *   - 返回 `true`：driver 继续处理剩余事件；
     *   - 返回 `false`：driver 立即停止（早退，不再取新事件）。
     *
     * 可抛异常 — 直接抛出会终止整个 driver 调用。
     */
    func parseError(err: XmlError): Bool
}

/**
 * 空实现基类。用户按需覆写其中几个方法即可，不必实现全部 11 个回调。
 *
 * `parseError` 的缺省行为是**把错误抛出来**：这让"不写任何代码"的 handler
 * 在遇到非良构输入时仍然会得到一个可观察的异常，而不是静默跳过。
 * 想要采集或忽略错误的调用方应覆写此方法。
 */
public open class DefaultSaxHandler <: SaxHandler {
    public DefaultSaxHandler() {}

    public open func startDocument(decl: XmlDecl): Unit { let _ = decl }
    public open func endDocument(pos: Position): Unit { let _ = pos }
    public open func startElement(
        pos: Position,
        name: QName,
        attrs: Array<Attribute>,
        ns: NsContext
    ): Unit {
        let _ = (pos, name, attrs, ns)
    }
    public open func endElement(pos: Position, name: QName): Unit { let _ = (pos, name) }
    public open func characters(pos: Position, text: String): Unit { let _ = (pos, text) }
    public open func cdata(pos: Position, text: String): Unit { let _ = (pos, text) }
    public open func comment(pos: Position, text: String): Unit { let _ = (pos, text) }
    public open func processingInstruction(
        pos: Position, target: String, data: String
    ): Unit {
        let _ = (pos, target, data)
    }
    public open func doctype(pos: Position, name: String): Unit { let _ = (pos, name) }
    public open func entityReference(pos: Position, name: String): Unit {
        let _ = (pos, name)
    }

    public open func parseError(err: XmlError): Bool {
        throw XmlException(err)
    }
}

/**
 * 把 `Iterator<SaxEvent>` 分发到 `SaxHandler` 的驱动器。
 *
 * `drive` 为线性循环，不做任何状态校验（合法性由 parser 负责）：
 * 一事件 → 一回调。
 *
 * 若 `parseError` 返回 `false`，driver 立即结束，后续事件不再拉取。
 */
public class SaxDriver {
    private SaxDriver() {}

    /** 把事件流分发到 handler。parser 抛异常会透传给调用方。 */
    public static func drive(events: Iterator<SaxEvent>, handler: SaxHandler): Unit {
        while (let Some(e) <- events.next()) {
            if (!dispatch(e, handler)) {
                return
            }
        }
    }

    /** 便捷入口：解析字符串 + 驱动 handler。 */
    public static func parseString(
        s: String,
        handler: SaxHandler,
        opts!: ParserOptions = ParserOptions()
    ): Unit {
        let p = XmlParser.fromString(s, opts: opts)
        drive(p, handler)
    }

    /** 返回 `true` = 继续；`false` = 早退（仅 ParseError 且 handler 返 false）。 */
    private static func dispatch(e: SaxEvent, h: SaxHandler): Bool {
        match (e) {
            case StartDocument(d) =>
                h.startDocument(d)
                return true
            case EndDocument(p) =>
                h.endDocument(p)
                return true
            case StartElement(p, n, attrs, ns) =>
                h.startElement(p, n, attrs, ns)
                return true
            case EndElement(p, n) =>
                h.endElement(p, n)
                return true
            case Characters(p, s) =>
                h.characters(p, s)
                return true
            case Cdata(p, s) =>
                h.cdata(p, s)
                return true
            case CommentEvent(p, s) =>
                h.comment(p, s)
                return true
            case Pi(p, t, d) =>
                h.processingInstruction(p, t, d)
                return true
            case Doctype(p, n) =>
                h.doctype(p, n)
                return true
            case EntityReference(p, n) =>
                h.entityReference(p, n)
                return true
            case ParseError(err) =>
                return h.parseError(err)
        }
    }
}
