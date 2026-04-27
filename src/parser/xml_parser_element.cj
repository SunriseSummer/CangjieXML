package fastxml.parser

import fastxml.dom.*
import fastxml.error.*

/**
 * `XmlParser` 的元素级解析：元素、属性、子节点扫描、文本、闭合标签。
 *
 * 与 `xml_parser_toplevel.cj` 同样以 `extend XmlParser` 挂回同一个类。
 */
extend XmlParser {
    public func parseElement(startPos: SourcePos, depth: Int64): XmlElement {
        if (depth > opts.maxElementDepth) {
            throw XmlParseException(ElementDepthExceeded(opts.maxElementDepth, startPos))
        }
        let name = readName()
        let el = doc.createElement(name)
        parseAttributes(el)
        cur.skipWhitespace()
        if (matchesChar(CH_SLASH)) {
            cur.advance()
            consumeExpected(CH_GT)
            return el
        }
        consumeExpected(CH_GT)
        parseElementChildren(el, startPos, name, depth)
        el
    }

    public func parseAttributes(el: XmlElement): Unit {
        while (true) {
            cur.skipWhitespace()
            if (cur.eof()) {
                throw XmlParseException(InvalidAttribute("(?)", cur.pos(), "unexpected EOF inside start tag"))
            }
            let r = cur.runes[cur.idx]
            if (r == CH_GT || r == CH_SLASH) {
                return
            }
            parseOneAttribute(el)
        }
    }

    public func parseOneAttribute(el: XmlElement): Unit {
        let attrPos = cur.pos()
        let attrName = readName()
        cur.skipWhitespace()
        if (!matchesChar(CH_EQUALS)) {
            throw XmlParseException(InvalidAttribute(attrName, attrPos, "expected '=' after attribute name"))
        }
        cur.advance()
        cur.skipWhitespace()
        let raw = readQuotedAttrValue(attrName, attrPos)
        let decoded = decodeEntitiesOrRethrowAttr(raw, attrName, attrPos)
        // 一次查询完成 dup-check + 插入，避免 hasAttribute + setAttribute 的两次 HashMap 查找。
        if (!el.tryAddAttribute(attrName, decoded)) {
            throw XmlParseException(InvalidAttribute(attrName, attrPos, "duplicate attribute"))
        }
    }

    public func decodeEntitiesOrRethrowAttr(raw: String, attrName: String, attrPos: SourcePos): String {
        try {
            decodeEntities(raw, attrPos)
        } catch (e: XmlParseException) {
            throw XmlParseException(InvalidAttribute(attrName, attrPos, e.error.toString()))
        }
    }

    public func readQuotedAttrValue(attrName: String, attrPos: SourcePos): String {
        if (cur.eof()) {
            throw XmlParseException(InvalidAttribute(attrName, attrPos, "unexpected EOF inside attribute value"))
        }
        let quoteCh = cur.runes[cur.idx]
        if (quoteCh == CH_QUOT || quoteCh == CH_APOS) {
            cur.advance()
        } else {
            throw XmlParseException(InvalidAttribute(attrName, attrPos, "attribute value must be quoted"))
        }
        let start = cur.idx
        let foundQuote = cur.skipAttrValueChars(quoteCh)
        if (!foundQuote) {
            if (cur.matches(CH_LT)) {
                throw XmlParseException(
                    InvalidAttribute(attrName, cur.pos(), "'<' is not allowed inside an attribute value"))
            }
            throw XmlParseException(InvalidAttribute(attrName, attrPos, "unterminated attribute value"))
        }
        let value = cur.sliceString(start, cur.idx)
        cur.advance()
        value
    }

    public func parseElementChildren(el: XmlElement, openPos: SourcePos, openName: String, depth: Int64): Unit {
        while (true) {
            if (cur.eof()) {
                throw XmlParseException(MismatchedElement(openName, "(EOF)", openPos))
            }
            if (!matchesChar(CH_LT)) {
                let text = parseTextBody()
                if (shouldKeepTextNode(text)) {
                    el.appendChild(text)
                }
                continue
            }
            if (cur.matchesAt(1, CH_SLASH)) {
                consumeEndTag(openPos, openName)
                return
            }
            el.appendChild(parseElementLevelMarkup(depth))
        }
    }

    public func parseElementLevelMarkup(depth: Int64): XmlNode {
        let startPos = cur.pos()
        consumeExpected(CH_LT)
        if (cur.eof()) {
            throw XmlParseException(InvalidText(startPos, "unexpected EOF after '<'"))
        }
        let r = cur.runes[cur.idx]
        if (r == CH_QUESTION) {
            consumeExpected(CH_QUESTION)
            return parsePiInsideElement(startPos)
        }
        if (r == CH_BANG) {
            return parseBangMarkup(startPos, atTop: false)
        }
        parseElement(startPos, depth + 1)
    }

    public func parsePiInsideElement(startPos: SourcePos): XmlNode {
        let payloadStart = cur.idx
        while (!cur.eof()) {
            if (cur.matches(CH_QUESTION) && cur.matchesAt(1, CH_GT)) {
                let payload = cur.sliceString(payloadStart, cur.idx)
                cur.advance()
                cur.advance()
                return doc.createUnknown("?${payload}?")
            }
            cur.advance()
        }
        throw XmlParseException(InvalidUnknownNode(startPos, "unterminated processing instruction inside element"))
    }

    public func parseTextBody(): XmlText {
        let textPos = cur.pos()
        let start = cur.idx
        cur.skipUntilLt()
        let raw = cur.sliceString(start, cur.idx)
        let decoded = decodeEntities(raw, textPos)
        let finalText = match (opts.whitespace) {
            case Preserve => decoded
            case Collapse => collapseWhitespace(decoded)
        }
        doc.createText(finalText)
    }

    public func shouldKeepTextNode(t: XmlText): Bool {
        match (opts.whitespace) {
            case Preserve => true
            case Collapse => !isAllWhitespace(t.value)
        }
    }

    public func consumeEndTag(openPos: SourcePos, openName: String): Unit {
        consumeExpected(CH_LT)
        consumeExpected(CH_SLASH)
        let closeName = readName()
        cur.skipWhitespace()
        consumeExpected(CH_GT)
        if (closeName != openName) {
            throw XmlParseException(MismatchedElement(openName, closeName, openPos))
        }
    }
}
