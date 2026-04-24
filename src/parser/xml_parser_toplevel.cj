package cangjie_xml.parser

import cangjie_xml.dom.*
import cangjie_xml.error.*

/**
 * `XmlParser` 的文档级与非元素节点解析逻辑。
 *
 * 与 `xml_parser_element.cj` 对应——两者均以 `extend XmlParser` 方式挂回同一类，
 * 对调用方无差别；分文件是为了把单源文件控制在 300 行内。
 */
extend XmlParser {

    /**
     * 公共入口：解析整个文档到 `doc`。
     *
     * 副作用：如果输入以 UTF-8 BOM 起首（且 `acceptBom` 为真），
     * 会把 `doc.hasBom` 置为 `true`，保证 parse→write 的往返可保留 BOM。
     * `writeBom`（写出时是否发 BOM）保持不变——调用方按需显式开启。
     */
    public func parseDocument(): Unit {
        if (cur.sawBom) {
            doc.hasBom = true
        }
        cur.skipWhitespace()
        if (cur.eof()) {
            throw XmlParseException(EmptyDocument)
        }
        parseTopLevelNodes()
        if (doc.rootElement.isNone()) {
            throw XmlParseException(EmptyDocument)
        }
    }

    public func parseTopLevelNodes(): Unit {
        var sawRoot = false
        while (!cur.eof()) {
            cur.skipWhitespace()
            if (cur.eof()) { return }
            if (!matchesChar(CH_LT)) {
                throw XmlParseException(
                    InvalidText(cur.pos(),
                        "unexpected text at top level (only elements / declarations / comments / DOCTYPE allowed here)"))
            }
            let node = parseMarkupAtTop(sawRoot)
            if (let Element(_) <- node.kind()) {
                sawRoot = true
            }
            doc.appendChild(node)
        }
    }

    public func parseMarkupAtTop(rootSeenAlready: Bool): XmlNode {
        let startPos = cur.pos()
        consumeExpected(CH_LT)
        match (cur.peek()) {
            case Some(r) =>
                if (r == CH_QUESTION) { return parsePiOrDeclarationTop(startPos) }
                if (r == CH_BANG)     { return parseBangMarkup(startPos, atTop: true) }
                if (r == CH_SLASH) {
                    throw XmlParseException(
                        MismatchedElement("(none)", peekSkippedName(), startPos))
                }
                if (rootSeenAlready) {
                    throw XmlParseException(
                        InvalidText(startPos, "only one root element is allowed"))
                }
                return parseElement(startPos, 1)
            case None =>
                throw XmlParseException(
                    InvalidText(startPos, "unexpected EOF after '<'"))
        }
    }

    public func parsePiOrDeclarationTop(startPos: SourcePos): XmlNode {
        consumeExpected(CH_QUESTION)
        let payloadStart = cur.idx
        while (!cur.eof()) {
            if (matchesChar(CH_QUESTION) && cur.peekAt(1) == Some(CH_GT)) {
                let payload = cur.sliceString(payloadStart, cur.idx)
                cur.advance()
                cur.advance()
                let trimmed = trimLeft(payload)
                if (trimmed.startsWith("xml") && isDeclarationPayload(trimmed)) {
                    return doc.createDeclaration(value: Some(payload))
                }
                return doc.createUnknown("?${payload}?")
            }
            cur.advance()
        }
        throw XmlParseException(
            InvalidDeclaration(startPos, "unterminated processing instruction / declaration"))
    }

    public func parseBangMarkup(startPos: SourcePos, atTop!: Bool): XmlNode {
        consumeExpected(CH_BANG)
        if (cur.consumeIfMatch(COMMENT_OPEN_DASHES)) {
            return parseCommentBody(startPos)
        }
        if (cur.consumeIfMatch(CDATA_PROLOGUE)) {
            if (atTop) {
                throw XmlParseException(
                    InvalidText(startPos, "CDATA is not allowed at document top level"))
            }
            return parseCdataBody(startPos)
        }
        return parseUnknownBangBody(startPos)
    }

    public func parseCommentBody(startPos: SourcePos): XmlNode {
        let start = cur.idx
        while (!cur.eof()) {
            if (cur.consumeIfMatch(COMMENT_EPILOGUE)) {
                return doc.createComment(cur.sliceString(start, cur.idx - EPILOGUE_LEN))
            }
            cur.advance()
        }
        throw XmlParseException(InvalidComment(startPos, "unterminated comment"))
    }

    public func parseCdataBody(startPos: SourcePos): XmlNode {
        let start = cur.idx
        while (!cur.eof()) {
            if (cur.consumeIfMatch(CDATA_EPILOGUE)) {
                return doc.createText(cur.sliceString(start, cur.idx - EPILOGUE_LEN), cdata: true)
            }
            cur.advance()
        }
        throw XmlParseException(InvalidText(startPos, "unterminated CDATA section"))
    }

    public func parseUnknownBangBody(startPos: SourcePos): XmlNode {
        let start = cur.idx
        var depth: Int64 = 0
        while (let Some(r) <- cur.peek()) {
            if (r == r'[') {
                depth++
            } else if (r == r']' && depth > 0) {
                depth--
            } else if (r == CH_GT && depth == 0) {
                let body = cur.sliceString(start, cur.idx)
                cur.advance()
                return doc.createUnknown("!${body}")
            }
            cur.advance()
        }
        throw XmlParseException(InvalidUnknownNode(startPos, "unterminated '<!' markup"))
    }

    /** 只用于错误消息：读取 `</name>` 里 `/` 后的名字片段。 */
    public func peekSkippedName(): String {
        let sb = StringBuilder()
        cur.advance() // skip '/'
        while (let Some(r) <- cur.peek()) {
            if (isNameChar(r) || isNameStart(r)) {
                sb.append(r)
                cur.advance()
            } else {
                break
            }
        }
        sb.toString()
    }
}
