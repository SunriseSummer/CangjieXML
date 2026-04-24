/*
 * parser — XmlParser XML 声明解析
 *
 * 拆自原 `xml_parser.cj` 的 `parseXmlDecl`。把原本嵌套三层、圈复杂度 ~18 的单个
 * match 分解为 per-attribute 校验函数（每个 ≤ 10 行）+ 小调度器。
 */
package cangjie_xml.parser

import std.collection.*
import cangjie_xml.core.*

/** XML 声明解析过程中的状态累积器。 */
class XmlDeclState {
    var version: String = "1.0"
    var sawVersion: Bool = false
    var encoding: ?String = None
    var standalone: Standalone = Standalone.Unspecified

    init() {}

    func toDecl(startPos: Position): XmlDecl {
        return XmlDecl(
            version: version,
            encoding: encoding,
            standalone: standalone,
            position: startPos
        )
    }

    /** 在此状态上应用 `name=value` 属性。 */
    func apply(name: String, value: String, pos: Position): Unit {
        match (name) {
            case "version" => applyVersion(value, pos)
            case "encoding" => applyEncoding(value, pos)
            case "standalone" => applyStandalone(value, pos)
            case _ =>
                throw XmlException(XmlError.Malformed(pos, "unexpected attribute '${name}' in XML declaration"))
        }
    }

    private func applyVersion(value: String, pos: Position): Unit {
        if (value != "1.0" && value != "1.1") {
            throw XmlException(XmlError.Malformed(pos, "unsupported XML version '${value}'"))
        }
        if (encoding.isSome() || !isUnspecified(standalone)) {
            throw XmlException(XmlError.Malformed(pos, "'version' must be the first attribute of XML declaration"))
        }
        version = value
        sawVersion = true
    }

    private func applyEncoding(value: String, pos: Position): Unit {
        if (!sawVersion) {
            throw XmlException(XmlError.Malformed(pos, "'encoding' must follow 'version' in XML declaration"))
        }
        if (!isUnspecified(standalone)) {
            throw XmlException(XmlError.Malformed(pos, "'encoding' must precede 'standalone' in XML declaration"))
        }
        if (!isValidEncodingName(value)) {
            throw XmlException(XmlError.Malformed(pos, "invalid encoding name '${value}'"))
        }
        encoding = Some(value)
    }

    private func applyStandalone(value: String, pos: Position): Unit {
        if (!sawVersion) {
            throw XmlException(XmlError.Malformed(pos, "'standalone' must follow 'version' in XML declaration"))
        }
        match (value) {
            case "yes" => standalone = Standalone.Yes
            case "no" => standalone = Standalone.No
            case _ =>
                throw XmlException(XmlError.Malformed(pos, "'standalone' must be 'yes' or 'no'"))
        }
    }

    private static func isUnspecified(s: Standalone): Bool {
        match (s) {
            case Unspecified => return true
            case _ => return false
        }
    }
}

extend XmlParser {
    /**
     * 从已消费 `<?xml` 之后开始解析，消费到 `?>` 为止；返回 XmlDecl。
     */
    func parseXmlDecl(startPos: Position): XmlDecl {
        let state = XmlDeclState()
        let seen = HashSet<String>()
        while (true) {
            let tok = readToken()
            match (tok) {
                case XmlDeclEnd(_) => break
                case AttrName(p, name) =>
                    rejectDuplicateXmlDeclAttr(seen, name, p)
                    consumeEqToken()
                    let value = readQuotedAttrValueLiteral(p)
                    state.apply(name, value, p)
                case t =>
                    throw XmlException(XmlError.Malformed(t.position(), "unexpected token in XML declaration"))
            }
        }
        if (!state.sawVersion) {
            throw XmlException(XmlError.Malformed(startPos, "XML declaration missing 'version'"))
        }
        return state.toDecl(startPos)
    }

    private static func rejectDuplicateXmlDeclAttr(seen: HashSet<String>, name: String, pos: Position): Unit {
        if (seen.contains(name)) {
            throw XmlException(XmlError.Malformed(pos, "duplicate XML declaration attribute '${name}'"))
        }
        seen.add(name)
    }

    private func consumeEqToken(): Unit {
        consumeExpectedToken({ t: Token =>
            match (t) {
                case AttrEq(_) => return true
                case _ => return false
            }
        }, "'=' after XML declaration attribute")
    }
}
