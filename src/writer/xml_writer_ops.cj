/*
 * writer — XmlWriter：状态机 + 写入实现（extend）
 *
 * 负责全部写入动作。主类体受 Cangjie 约束（无法调 extend 成员），通过包级
 * `writerXxx` 函数桥接。
 *
 * 所有错误路径统一走 `fail(msg)`，抛 `XmlException(XmlError.Other(...))`
 * 并把状态置 `Faulted`。
 */
package cangjie_xml.writer

import cangjie_xml.core.*

extend XmlWriter {
    /* ---------- 工具：抛错 + 字节写入 ---------- */

    func fail(msg: String): Nothing {
        state = WriterState.Faulted
        throw XmlException(XmlError.Other(Position.unknown(), msg))
    }

    func requireAlive(): Unit {
        match (state) {
            case Closed => fail("write on closed XmlWriter")
            case Faulted => fail("write on faulted XmlWriter")
            case _ => ()
        }
    }

    func writeStr(s: String): Unit {
        sink.write(s.toArray())
    }

    func writeByteArray(b: Array<Byte>): Unit {
        sink.write(b)
    }

    /* ---------- XML 声明 ---------- */

    func runWriteXmlDeclaration(version: String, encoding: ?String, standalone: Standalone3): Unit {
        requireAlive()
        if (opts.omitXmlDeclaration) {
            fail("XML declaration suppressed by WriterOptions.omitXmlDeclaration")
        }
        if (state != WriterState.Start) {
            fail("writeXmlDeclaration must be the first write")
        }
        writeStr("<?xml version=\"")
        writeStr(version)
        writeStr(r'"'.toString())
        match (encoding) {
            case Some(e) =>
                writeStr(" encoding=\"")
                writeStr(e)
                writeStr(r'"'.toString())
            case None => ()
        }
        match (standalone) {
            case Yes => writeStr(" standalone=\"yes\"")
            case No => writeStr(" standalone=\"no\"")
            case Unspecified => ()
        }
        writeStr("?>")
        if (opts.indent) {
            writeStr(opts.lineSeparator)
        }
        state = WriterState.Prolog
    }

    /* ---------- DOCTYPE ---------- */

    func runWriteDoctype(name: String): Unit {
        requireAlive()
        if (state != WriterState.Start && state != WriterState.Prolog) {
            fail("writeDoctype must appear before the root element")
        }
        writeStr("<!DOCTYPE ")
        writeStr(name)
        writeStr(r'>'.toString())
        if (opts.indent) {
            writeStr(opts.lineSeparator)
        }
        state = WriterState.Prolog
    }

    /* ---------- 元素 open / 属性 / 元素 close ---------- */

    func runStartElement(lexicalName: String): Unit {
        requireAlive()
        match (state) {
            case Start => () // 根元素，允许
            case Prolog => () // 声明 / DOCTYPE / 注释之后，允许
            case InElementOpen =>
                // 父开标签未关；关闭后再进入子元素
                writeStr(r'>'.toString())
                stack.markNonLeafChild()
            case InElementContent =>
                stack.markNonLeafChild()
            case Epilog => fail("only one root element allowed; cannot startElement after the root closed")
            case _ => ()
        }
        writeIndentBeforeElement()
        writeStr(r'<'.toString())
        writeStr(lexicalName)
        stack.push(ElementFrame(lexicalName))
        state = WriterState.InElementOpen
    }

    func runWriteAttribute(name: String, value: String): Unit {
        requireAlive()
        if (state != WriterState.InElementOpen) {
            fail("writeAttribute must immediately follow startElement")
        }
        writeStr(r' '.toString())
        writeStr(name)
        writeStr("=\"")
        writeStr(escapeXml(value, forAttribute: true))
        writeStr(r'"'.toString())
    }

    func runEndElement(): Unit {
        requireAlive()
        if (stack.isEmpty()) {
            fail("endElement without matching startElement")
        }
        let frame = stack.pop()
        match (state) {
            case InElementOpen =>
                // 未写任何子节点 → 自闭合
                writeStr("/>")
            case InElementContent =>
                // 若元素仅含文本 / CDATA（leafTextOnly），保持同行；否则缩进到新行
                if (!frame.leafTextOnly) {
                    writeIndentAt(stack.size())
                }
                writeStr("</")
                writeStr(frame.lexicalName)
                writeStr(r'>'.toString())
            case _ => fail("endElement in invalid state")
        }
        if (stack.isEmpty()) {
            state = WriterState.Epilog
        } else {
            state = WriterState.InElementContent
        }
    }

    /* ---------- 文本 / CDATA / Comment / PI ---------- */

    func runWriteText(data: String): Unit {
        requireAlive()
        closePendingStartTagForContent()
        if (state != WriterState.InElementContent) {
            fail("writeText requires an open element")
        }
        writeStr(escapeXml(data))
        stack.markAnyChild()
    }

    func runWriteCdata(data: String): Unit {
        requireAlive()
        closePendingStartTagForContent()
        if (state != WriterState.InElementContent) {
            fail("writeCdata requires an open element")
        }
        if (data.contains("]]>")) {
            fail("CDATA section must not contain the sequence ']]>'")
        }
        writeStr("<![CDATA[")
        writeStr(data)
        writeStr("]]>")
        stack.markAnyChild()
    }

    func runWriteComment(data: String): Unit {
        requireAlive()
        if (data.contains("--")) {
            fail("comment must not contain the sequence '--'")
        }
        onStandaloneNodeStateTransition()
        writeIndentBeforeElement()
        writeStr("<!--")
        writeStr(data)
        writeStr("-->")
        onStandaloneNodeStateCommit()
    }

    func runWritePi(target: String, data: ?String): Unit {
        requireAlive()
        validatePiTarget(target)
        match (data) {
            case Some(s) where s.contains("?>") =>
                fail("PI data must not contain the sequence '?>'")
            case _ => ()
        }
        onStandaloneNodeStateTransition()
        writeIndentBeforeElement()
        writeStr("<?")
        writeStr(target)
        match (data) {
            case Some(s) where s.size > 0 =>
                writeStr(r' '.toString())
                writeStr(s)
            case _ => ()
        }
        writeStr("?>")
        onStandaloneNodeStateCommit()
    }

    func runWriteRawBytes(bytes: Array<Byte>): Unit {
        requireAlive()
        closePendingStartTagForContent()
        match (state) {
            case Start | Prolog | Epilog | InElementContent => ()
            case _ => fail("writeRawBytes in invalid state")
        }
        writeByteArray(bytes)
        if (state == WriterState.InElementContent) {
            stack.markAnyChild()
            stack.markNonLeafChild()
        }
    }

    /* ---------- Close ---------- */

    func runClose(): Unit {
        if (state == WriterState.Closed) {
            return
        }
        if (state == WriterState.Faulted) {
            // 允许对 faulted 实例再 close，不再抛错；只记状态。
            state = WriterState.Closed
            return
        }
        if (!stack.isEmpty()) {
            let name = stack.top().lexicalName
            fail("close() with ${stack.size()} unclosed element(s); top = '${name}'")
        }
        sink.flush()
        state = WriterState.Closed
    }

    /* ---------- 辅助：状态转移 + 缩进 ---------- */

    /**
     * Comment / PI 的前状态处理：
     *   - 在 `InElementOpen` 里，先关掉父开标签；
     *   - 在 `InElementContent` 里，把栈顶 `leafTextOnly` 置 false。
     */
    func onStandaloneNodeStateTransition(): Unit {
        match (state) {
            case Start => ()
            case Prolog | Epilog => ()
            case InElementOpen =>
                writeStr(r'>'.toString())
                stack.markNonLeafChild()
            case InElementContent =>
                stack.markNonLeafChild()
            case _ => ()
        }
    }

    /** Comment / PI 写完后把状态切到合适的"内容"阶段。 */
    func onStandaloneNodeStateCommit(): Unit {
        match (state) {
            case Start => state = WriterState.Prolog
            case Prolog => () // 仍在 prolog
            case InElementOpen =>
                // 不应出现：onStandaloneNodeStateTransition 已把它转成了 InElementContent
                state = WriterState.InElementContent
            case InElementContent => ()
            case Epilog => () // 仍在 epilog
            case _ => ()
        }
    }

    /**
     * `writeText` / `writeCdata` / `writeRawBytes(content)` 的状态过渡：
     * 如果仍处于 `InElementOpen`，把 `>` 写出并切到 content。
     */
    func closePendingStartTagForContent(): Unit {
        if (state == WriterState.InElementOpen) {
            writeStr(r'>'.toString())
            state = WriterState.InElementContent
        }
    }

    /**
     * 元素 / Comment / PI 前的缩进：
     *   - `indent=false`：不插入任何空白；
     *   - 顶层 Epilog：不再加缩进前导换行（与 save 包一致，避免在 epilog 增加
     *     多余空白）；
     *   - 其它：换行 + `stack.size()` 份 `indentString`。
     */
    func writeIndentBeforeElement(): Unit {
        if (!opts.indent) {
            return
        }
        // Start 状态下，若还没写任何字节，不预先换行
        if (state == WriterState.Start && stack.isEmpty()) {
            return
        }
        writeIndentAt(stack.size())
    }

    func writeIndentAt(depth: Int64): Unit {
        if (!opts.indent) {
            return
        }
        writeStr(opts.lineSeparator)
        var i = 0
        while (i < depth) {
            writeStr(opts.indentString)
            i += 1
        }
    }

    /* ---------- PI 目标简单校验 ---------- */

    /**
     * PI 目标必须是合法 NCName 且不是 "xml" 系列保留（不区分大小写）——
     * 这与 libxml2 / XML 1.0 §2.6 一致。本阶段不做完整 NCName 校验，
     * 只拦最明显的两类：空字符串 + "xml" 保留名。
     */
    func validatePiTarget(target: String): Unit {
        if (target.size == 0) {
            fail("PI target must not be empty")
        }
        let lower = target.toAsciiLower()
        if (lower == "xml") {
            fail("PI target 'xml' is reserved")
        }
    }
}
