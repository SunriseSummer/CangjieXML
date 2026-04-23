/*
 * parser — XmlParser 文本 / 实体 / Characters 合并路径
 *
 * 拆自原 `xml_parser.cj` 的 `handleText` / `handleEntityRef` / `mergeOrEmitCharacters`
 * / `flushPendingCharacters` / `expandEntityText` / `bumpEntityExpansion` /
 * `readQuotedAttrValueLiteral`。所有涉及字符级累积 + Billion Laughs 计数 + 预定义实体展开
 * 的逻辑都汇聚于此。
 */
package cangjie_xml.parser

import cangjie_xml.core.*

extend XmlParser {
    /* ---------- Text / CharRef / EntityRef 合并产出 ---------- */

    func handleText(pos: Position, s: String): Unit {
        if (s.size == 0) {
            return
        }
        if (elemStack.isEmpty()) {
            // 根元素外：只允许空白；空白则悄悄丢弃（序言 / 跋）
            if (!isAllXmlWhitespace(s)) {
                throw XmlException(XmlError.Malformed(pos, "non-whitespace text outside root element"))
            }
            return
        }
        if (!opts.keepBlanks && isAllXmlWhitespace(s)) {
            return
        }
        mergeOrEmitCharacters(pos, s)
    }

    func handleEntityRef(pos: Position, name: String): Unit {
        if (elemStack.isEmpty()) {
            throw XmlException(XmlError.Malformed(pos, "entity reference outside root element"))
        }
        if (!opts.substituteEntities) {
            flushPendingCharacters()
            pending.addLast(SaxEvent.EntityReference(pos, name))
            return
        }
        let text = expandEntityText(name, pos)
        if (text.size != 0) {
            mergeOrEmitCharacters(pos, text)
        }
    }

    /** 追加到"待 flush 字符缓冲"；一旦遇到分隔事件（见 `postReadHook`）才产出 Characters。 */
    func mergeOrEmitCharacters(pos: Position, s: String): Unit {
        pendingCharsPos = match (pendingCharsPos) {
            case None => Some(pos)
            case other => other
        }
        pendingCharsBuf.append(s)
    }

    func flushPendingCharacters(): Unit {
        match (pendingCharsPos) {
            case None => return
            case Some(p) =>
                let text = pendingCharsBuf.toString()
                if (text.size > 0) {
                    pending.addLast(SaxEvent.Characters(p, text))
                }
                pendingCharsBuf.reset()
                pendingCharsPos = None
        }
    }

    /* ---------- 实体展开 ---------- */

    /** 预定义 / 用户文本实体展开；同时做 Billion-Laughs 计数。 */
    func expandEntityText(name: String, pos: Position): String {
        match (resolver.resolveEntity(name)) {
            case Some(Text(s)) =>
                bumpEntityExpansion(Int64(s.size), pos)
                return s
            case Some(External(_, _, _)) =>
                throw XmlException(XmlError.Malformed(pos, "external entity '${name}' not supported in this iteration"))
            case None =>
                throw XmlException(XmlError.Malformed(pos, "undefined entity '${name}'"))
        }
    }

    /** 增加字符展开计数；超过 `maxEntityExpansion` 抛 LimitExceeded。 */
    func bumpEntityExpansion(n: Int64, pos: Position): Unit {
        entityExpansionCharCount += n
        if (entityExpansionCharCount > opts.maxEntityExpansion) {
            throw XmlException(XmlError.LimitExceeded(pos, "entity expansion total exceeded ${opts.maxEntityExpansion}"))
        }
    }

    /* ---------- 属性值字面量 ---------- */

    /**
     * 折叠 `AttrValueStart` + (`AttrValueChunk` | `CharRef` | `EntityRef`)* + `AttrValueEnd`
     * 序列为单个字符串。XML 声明 / 普通属性共用此路径。
     */
    func readQuotedAttrValueLiteral(attrNamePos: Position): String {
        consumeExpectedToken({ t: Token =>
            match (t) {
                case AttrValueStart(_, _) => return true
                case _ => return false
            }
        }, "opening quote of attribute value")
        return collectAttrValueBody(attrNamePos)
    }

    private func collectAttrValueBody(attrNamePos: Position): String {
        let sb = StringBuilder()
        while (true) {
            let t = readToken()
            match (t) {
                case AttrValueEnd(_, _) => return sb.toString()
                case AttrValueChunk(_, s) => sb.append(s)
                case CharRef(_, cp) =>
                    sb.append(Rune(UInt32(cp)))
                    bumpEntityExpansion(1, attrNamePos)
                case EntityRef(p, name) =>
                    sb.append(expandEntityText(name, p))
                case other =>
                    throw XmlException(XmlError.Malformed(other.position(), "unexpected token in attribute value"))
            }
        }
        return sb.toString()
    }
}
