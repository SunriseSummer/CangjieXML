/*
 * parser — XmlParser 辅助：QName / 命名空间绑定 / 字符分类 / intern
 *
 * 拆自原 `xml_parser.cj` 的"命名空间 / QName 解析"段落。保持为包级 / 私有静态工具，
 * 降低 `XmlParser` 类自身的行数与圈复杂度。
 */
package cangjie_xml.parser

import cangjie_xml.core.*

/* ------------------------------------------------------------------ */
/*  字符分类                                                            */
/* ------------------------------------------------------------------ */

/** 仅 ASCII 空白（SP / TAB / LF / CR），对应 XML 产生式 S。 */
func isAllXmlWhitespace(s: String): Bool {
    for (r in s.runes()) {
        let cp = Int32(UInt32(r))
        if (cp != CHAR_SPACE && cp != CHAR_HT && cp != CHAR_LF && cp != CHAR_CR) {
            return false
        }
    }
    return true
}

/** XML 声明中 encoding 属性值的语法合法性：`[A-Za-z][A-Za-z0-9._-]*`。 */
func isValidEncodingName(s: String): Bool {
    if (s.size == 0) {
        return false
    }
    var first = true
    for (r in s.runes()) {
        let cp = Int32(UInt32(r))
        let alpha = (cp >= CHAR_UPPER_A && cp <= CHAR_UPPER_Z) ||
            (cp >= CHAR_LOWER_A && cp <= CHAR_LOWER_Z)
        let digit = cp >= CHAR_DIGIT_0 && cp <= CHAR_DIGIT_9
        let sym = cp == CHAR_DOT || cp == CHAR_UNDERSCORE || cp == CHAR_MINUS
        if (first) {
            if (!alpha) {
                return false
            }
            first = false
        } else if (!(alpha || digit || sym)) {
            return false
        }
    }
    return true
}

/* ------------------------------------------------------------------ */
/*  xmlns 声明分类                                                      */
/* ------------------------------------------------------------------ */

/** xmlns 声明种类。 */
enum NsDeclKind {
    | NotNsDecl
    | DefaultNs
    | PrefixNs
}

/** 根据属性名判定种类。命名 / 拼串均在此处完成，避免调用方重复 startsWith。 */
func classifyNsDecl(name: String): NsDeclKind {
    if (name == "xmlns") {
        return NsDeclKind.DefaultNs
    }
    if (name.size > XMLNS_COLON_PREFIX_LEN && startsWithXmlnsColon(name)) {
        return NsDeclKind.PrefixNs
    }
    return NsDeclKind.NotNsDecl
}

private func startsWithXmlnsColon(name: String): Bool {
    // "xmlns:" 共 6 个 ASCII 字节
    if (name.size < XMLNS_COLON_PREFIX_LEN) {
        return false
    }
    return name[0] == UInt8(CHAR_LOWER_X) && name[1] == UInt8(CHAR_LOWER_M) &&
        name[2] == UInt8(CHAR_LOWER_L) && name[3] == UInt8(CHAR_LOWER_N) &&
        name[4] == UInt8(CHAR_LOWER_S) && name[5] == UInt8(CHAR_COLON)
}

/** 空串 → None，其余保留为 Some。 */
func emptyToNone(s: String): ?String {
    if (s.size == 0) {
        return None
    }
    return Some(s)
}

/** 命名空间 URI 不得含 NUL（XML 不允许的字符）。 */
func validateNsValue(s: String, pos: Position): Unit {
    for (r in s.runes()) {
        if (UInt32(r) == 0u32) {
            throw XmlException(XmlError.NamespaceError(pos, "namespace URI contains NUL"))
        }
    }
}

/* ------------------------------------------------------------------ */
/*  QName 拆分与解析                                                    */
/* ------------------------------------------------------------------ */

/** 把 `"prefix:local"` / `"local"` 拆成 `(?prefix, local)`，并做 NCName 约束校验。 */
func splitQName(raw: String, pos: Position): (?String, String) {
    let colonByteOff = findFirstColonByteOffset(raw)
    if (colonByteOff < 0) {
        return (None, raw)
    }
    let p = raw[..colonByteOff]
    let l = raw[(colonByteOff + 1)..]
    if (p.size == 0 || l.size == 0) {
        throw XmlException(XmlError.NamespaceError(pos, "invalid qualified name '${raw}'"))
    }
    // local 必须是 NCName：不得再含 ':'
    for (r in l.runes()) {
        if (Int32(UInt32(r)) == CHAR_COLON) {
            throw XmlException(XmlError.NamespaceError(pos, "qualified name '${raw}' has multiple colons"))
        }
    }
    return (Some(p), l)
}

private func findFirstColonByteOffset(raw: String): Int64 {
    var byteOff = 0
    for (r in raw.runes()) {
        if (Int32(UInt32(r)) == CHAR_COLON) {
            return byteOff
        }
        byteOff += runeByteLen(r)
    }
    return -1
}

private func runeByteLen(r: Rune): Int64 {
    let cp = UInt32(r)
    if (cp < UTF8_1BYTE_UPPER) {
        return 1
    }
    if (cp < UTF8_2BYTE_UPPER) {
        return 2
    }
    if (cp < UTF8_3BYTE_UPPER) {
        return 3
    }
    return 4
}

/** 解析一个 QName：拆分 + 绑定 URI（属性按 §6.2 不应用默认命名空间）。 */
func resolveQName(raw: String, ns: NsContext, pos: Position, isAttribute!: Bool): QName {
    let (prefix, local) = splitQName(raw, pos)
    let uri = bindPrefixUri(prefix, ns, pos, isAttribute)
    return QName(local, prefix: prefix, uri: uri)
}

private func bindPrefixUri(prefix: ?String, ns: NsContext, pos: Position, isAttribute: Bool): ?String {
    match (prefix) {
        case Some(p) =>
            match (ns.resolve(Some(p))) {
                case Some(u) => return Some(u)
                case None =>
                    throw XmlException(XmlError.NamespaceError(pos, "undefined namespace prefix '${p}'"))
            }
        case None =>
            if (isAttribute) {
                return None
            }
            return ns.defaultNs()
    }
}

/** 根据 `NameTable` 是否存在，对 QName 的 local / prefix 做 intern 或直接透传。 */
func maybeInternQName(q: QName, nt: ?NameTable): QName {
    match (nt) {
        case None => return q
        case Some(table) =>
            let localI = table.intern(q.localName)
            let prefixI = match (q.prefix) {
                case Some(p) => Some(table.intern(p))
                case None => None<String>
            }
            return QName(localI, prefix: prefixI, uri: q.uri)
    }
}
