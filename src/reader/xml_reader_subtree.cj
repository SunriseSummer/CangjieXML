/*
 * reader — XmlReader 子树提取 API（Phase 4c+）
 *
 * 对应 .NET `XmlReader.ReadOuterXml` / `ReadInnerXml` / `ReadSubtree` 与
 * libxml2 `xmlTextReaderReadOuterXml` / `xmlTextReaderReadInnerXml` /
 * `xmlTextReaderSubtree`（后者为 libxml 2.12 增补）。
 *
 * 公开 API：
 *   - `readOuterXml()`：返回当前 Element 的完整 XML 文本（含自身标签），
 *     游标前进到其配对 EndElement 之后。
 *   - `readInnerXml()`：返回当前 Element 所有子节点的序列化文本（不含自身标签），
 *     游标前进到其配对 EndElement 之后。
 *   - `readSubtree()`：返回一个独立的 `XmlReader`，专门遍历当前元素子树；
 *     调用方可以像正常 reader 一样走 read() / nodeType() 等；同时原 reader
 *     的游标已经前进到配对 EndElement 之后。
 *
 * 前置条件：
 *   - 三个 API 都要求 `nodeType() == Element`，否则抛 `XmlException(Other)`；
 *   - 空元素的 `readOuterXml` 返回 `<tag/>` 或 `<tag></tag>`（取决于源），
 *     `readInnerXml` 返回空串，`readSubtree` 返回的 sub-reader 只有一个
 *     Element 节点（且 `isEmptyElement() == true`）。
 *
 * 序列化格式：
 *   - 关闭缩进（默认 `SerializeOptions()`），最大限度保留源 XML 的字符语义；
 *   - 不写 `<?xml?>` 声明（`omitXmlDeclaration = true` 由 `elementToString`
 *     默认行为保证）；
 *   - 不做命名空间最小化；原属性原样输出。
 */
package cangjie_xml.reader

import std.collection.*
import cangjie_xml.core.*
import cangjie_xml.parser.*
import cangjie_xml.tree.*
import cangjie_xml.save.*

extend XmlReader {
    /* ---------- readOuterXml ---------- */

    /**
     * 返回当前 Element 的完整序列化 XML。调用后游标定位在配对 EndElement 之后
     * （等价 `skip()` + `read()` 的效果：下次 `read()` 会进入下一个兄弟节点或
     * 上一层的 EndElement）。
     *
     * 要求 `nodeType() == Element`，否则抛 `XmlException`。
     */
    public func readOuterXml(): String {
        requireOnElement("readOuterXml")
        let element = consumeCurrentElement()
        return DocumentSerializer.elementToString(element)
    }

    /* ---------- readInnerXml ---------- */

    /**
     * 返回当前 Element 的**内部** XML（所有直接子节点依次序列化的拼接，不含
     * 当前元素自己的 start/end 标签）。调用后游标定位在配对 EndElement 之后。
     *
     * 空元素返回空串。
     */
    public func readInnerXml(): String {
        requireOnElement("readInnerXml")
        let element = consumeCurrentElement()
        let sb = StringBuilder()
        for (c in element.children()) {
            sb.append(DocumentSerializer.nodeToString(c))
        }
        return sb.toString()
    }

    /* ---------- readSubtree ---------- */

    /**
     * 返回一个独立的 `XmlReader`，其事件源是当前 Element 子树的缓冲拷贝。
     * 原 reader 的游标前进到配对 EndElement 之后。
     *
     * sub-reader 的状态为 `Initial`；调用方 `read()` 后 `nodeType()` 开始为
     * `Element`（根就是原来的当前节点），之后按文档序遍历子孙。sub-reader 走
     * 到尽头后 `state = EndOfFile`。
     */
    public func readSubtree(): XmlReader {
        requireOnElement("readSubtree")
        // 空元素：直接把当前 event 做一条回放 —— 新建 reader 读到一个 Element
        // 即 EndOfFile（因为 parser 对 `<a/>` 也会发配对 EndElement，这里一并
        // 收入 buffer）。
        let buf = bufferCurrentElement()
        return XmlReader.fromEvents(BufferedEventsIterator(buf))
    }

    /* ---------- 内部：落实"消费当前 Element 子树"的共用路径 ---------- */

    /**
     * 要求当前光标是 Element；失败抛 `XmlException`。
     * 不允许在属性游标上调用（即使宿主是 Element 也拒绝）：与 .NET 行为一致。
     */
    func requireOnElement(op: String): Unit {
        if (attrCursor >= 0) {
            throw XmlException(XmlError.Other(Position.unknown(),
                "XmlReader.${op}: cannot be called while positioned on an attribute"))
        }
        match (current) {
            case Some(StartElement(_, _, _, _)) => ()
            case _ =>
                throw XmlException(XmlError.Other(Position.unknown(),
                    "XmlReader.${op}: current node is not an Element"))
        }
    }

    /**
     * 把当前 Element 的 StartElement + 子事件 + 配对 EndElement 构造成一棵
     * 独立 `Element`。调用后：
     *   - 原 reader 的 `current` 被置为配对的 EndElement（与 `skip()` 语义一致）；
     *   - `depthVal` / `emptyElement` 保持 EndElement 场景的语义（即 skip 之后
     *     再 read 时会自然 `depth -= 1`）。
     */
    func consumeCurrentElement(): Element {
        let startEv = current.getOrThrow()
        // 若是空元素，parser 已经把配对 EndElement 存进 peeked（由 runRead 中
        // `emptyElement = true` 路径预读产生）。SubtreeBuilder 正好需要它作为
        // 第二个事件读取，pullEvent 会优先走 peeked buffer。
        let el = buildElementFromEvents(startEv) { => pullEvent() }
        // 把 reader 的 current 设为"当前元素的配对 EndElement"——构造 Element 的
        // 最后一个被消费事件必然是对应 EndElement。为了让下一次 read() 正确 -1
        // depth，我们**合成**一个位置为 unknown 的 EndElement 放进 current。
        current = Some(SaxEvent.EndElement(Position.unknown(), startEv.startElementQName()))
        emptyElement = false
        attrCursor = -1
        state = ReaderState.Interactive
        return el
    }

    /**
     * 把当前 Element 的 StartElement + 子事件 + 配对 EndElement 按文档序收入
     * 一个 ArrayList，供 `readSubtree` 的 sub-reader 重放。
     */
    func bufferCurrentElement(): ArrayList<SaxEvent> {
        let startEv = current.getOrThrow()
        let buf = collectSubtreeEvents(startEv) { => pullEvent() }
        current = Some(SaxEvent.EndElement(Position.unknown(), startEv.startElementQName()))
        emptyElement = false
        attrCursor = -1
        state = ReaderState.Interactive
        return buf
    }
}

/* ---------- SaxEvent 迭代器包装：回放 ArrayList 供 sub-reader 使用 ---------- */

class BufferedEventsIterator <: Iterator<SaxEvent> {
    let buf: ArrayList<SaxEvent>
    var idx: Int64 = 0

    init(buf: ArrayList<SaxEvent>) {
        this.buf = buf
    }

    public func next(): ?SaxEvent {
        if (idx >= buf.size) {
            return None
        }
        let e = buf[idx]
        idx += 1
        return Some(e)
    }
}

/* ---------- SaxEvent 便捷工具：从 StartElement 取 QName ---------- */

extend SaxEvent {
    func startElementQName(): QName {
        match (this) {
            case StartElement(_, q, _, _) => return q
            case _ => return QName("")
        }
    }
}
