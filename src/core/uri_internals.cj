/*
 * core — URI 内部：解析器 + 归一化辅助
 *
 * 拆自原 `uri.cj` 的 `UriParser` 类以及 `mergePaths` / `removeDotSegments` /
 * `popLastSegment` / `normalizeAuthority` 私有函数。
 *
 * `removeDotSegments` 的原状态机（11 路 if-else）圈复杂度极高，本次拆为 6 个命名
 * 规则方法 + 主循环仅做顺序匹配，降低圈复杂度到每函数 ≤ 4。
 */
package cangjie_xml.core

/* ---------- 归一化辅助 ---------- */

/** RFC 3986 §5.2.3 Merge Paths。 */
func mergePaths(base: Uri, refPath: String): String {
    let hasAuthority = match (base.authority) {
        case Some(_) => true
        case None => false
    }
    if (hasAuthority && base.path.isEmpty()) {
        return "/" + refPath
    }
    match (base.path.lastIndexOf("/")) {
        case Some(idx) => return base.path[0..idx + 1] + refPath
        case None => return refPath
    }
}

/** RFC 3986 §5.2.4 Remove Dot Segments。 */
func removeDotSegments(input: String): String {
    var remaining = input
    let out = StringBuilder()
    while (!remaining.isEmpty()) {
        remaining = dotSegmentsStep(remaining, out)
    }
    return out.toString()
}

/** 对 `remaining` 应用 RFC 3986 §5.2.4 的一步规则，返回新的 remaining。 */
private func dotSegmentsStep(remaining: String, out: StringBuilder): String {
    // 规则 A
    if (remaining.startsWith("../")) {
        return remaining[3..remaining.size]
    }
    if (remaining.startsWith("./")) {
        return remaining[2..remaining.size]
    }
    // 规则 B
    if (remaining.startsWith("/./")) {
        return "/" + remaining[3..remaining.size]
    }
    if (remaining == "/.") {
        return "/"
    }
    // 规则 C
    if (remaining.startsWith("/../")) {
        popLastSegment(out)
        return "/" + remaining[4..remaining.size]
    }
    if (remaining == "/..") {
        popLastSegment(out)
        return "/"
    }
    // 规则 D：单纯的 "." / ".." 消费完
    if (remaining == "." || remaining == "..") {
        return ""
    }
    // 规则 E：移动第一段（含前导 "/"）
    return moveFirstSegment(remaining, out)
}

private func moveFirstSegment(remaining: String, out: StringBuilder): String {
    var pos = 0
    if (remaining[pos..pos + 1] == "/") {
        pos = 1
    }
    while (pos < remaining.size && remaining[pos..pos + 1] != "/") {
        pos += 1
    }
    out.append(remaining[0..pos])
    return remaining[pos..remaining.size]
}

/** 把 `out` 中的最后一个路径段（含前导 `/`）截掉。 */
func popLastSegment(out: StringBuilder): Unit {
    let s = out.toString()
    if (s.isEmpty()) {
        return
    }
    match (s.lastIndexOf("/")) {
        case Some(idx) =>
            out.reset()
            out.append(s[0..idx])
        case None => out.reset()
    }
}

/** 将 authority 中的 host 部分统一为小写；保留 userinfo / port 原样。 */
func normalizeAuthority(authority: String): String {
    let (userinfo, hostAndPort) = splitUserinfo(authority)
    let (host, port) = splitHostPort(hostAndPort)
    return joinAuthority(userinfo, host, port)
}

private func splitUserinfo(authority: String): (?String, String) {
    match (authority.indexOf("@")) {
        case Some(idx) => return (Some(authority[0..idx]), authority[idx + 1..authority.size])
        case None => return (None, authority)
    }
}

private func splitHostPort(hostAndPort: String): (String, ?String) {
    // IPv6 字面量以 '[' 开头，':' 只有在 ']' 之后才是端口分隔符
    if (hostAndPort.startsWith("[")) {
        return splitIPv6HostPort(hostAndPort)
    }
    match (hostAndPort.lastIndexOf(":")) {
        case Some(idx) => return (hostAndPort[0..idx], Some(hostAndPort[idx + 1..hostAndPort.size]))
        case None => return (hostAndPort, None)
    }
}

private func splitIPv6HostPort(hostAndPort: String): (String, ?String) {
    match (hostAndPort.indexOf("]")) {
        case Some(rb) =>
            let host = hostAndPort[0..rb + 1]
            if (rb + 1 < hostAndPort.size && hostAndPort[rb + 1..rb + 2] == ":") {
                return (host, Some(hostAndPort[rb + 2..hostAndPort.size]))
            }
            return (host, None)
        case None => return (hostAndPort, None)
    }
}

private func joinAuthority(userinfo: ?String, host: String, port: ?String): String {
    let sb = StringBuilder()
    match (userinfo) {
        case Some(u) =>
            sb.append(u)
            sb.append("@")
        case None => ()
    }
    sb.append(host.toAsciiLower())
    match (port) {
        case Some(p) =>
            sb.append(":")
            sb.append(p)
        case None => ()
    }
    return sb.toString()
}

/* ---------- UriParser ---------- */

/**
 * 线性递归下降 URI 解析器。对输入进行一次顺序扫描，按 RFC 3986
 * 附录 A ABNF 的顺序切分出各组件。不做百分号解码，交由 `normalize`。
 */
class UriParser {
    private let input: String
    private let runes: Array<Rune>
    private var pos: Int64

    init(input: String) {
        this.input = input
        this.runes = input.toRuneArray()
        this.pos = 0
    }

    func run(): Uri {
        let scheme = tryParseScheme()
        let (authority, path) = parseAuthorityAndPath()
        let query = parseOptionalQuery()
        let fragment = parseOptionalFragment()
        if (pos != runes.size) {
            throw XmlException(XmlError.UriError("unexpected trailing characters in URI: ${input}"))
        }
        return Uri(scheme: scheme, authority: authority, path: path, query: query, fragment: fragment)
    }

    private func parseAuthorityAndPath(): (?String, String) {
        if (consumePrefix("//")) {
            let a: ?String = Some(takeUntilAny("/?#"))
            let p = takeUntilAny("?#")
            return (a, p)
        }
        return (None, takeUntilAny("?#"))
    }

    private func parseOptionalQuery(): ?String {
        if (consume(r'?')) {
            return Some(takeUntilAny("#"))
        }
        return None
    }

    private func parseOptionalFragment(): ?String {
        if (consume(r'#')) {
            let f: ?String = Some(remaining())
            pos = runes.size
            return f
        }
        return None
    }

    /** 尝试解析 scheme 部分（ALPHA *(ALPHA / DIGIT / "+" / "-" / ".")）。 */
    private func tryParseScheme(): ?String {
        if (pos >= runes.size || !isAlpha(runes[pos])) {
            return None
        }
        var end = pos + 1
        while (end < runes.size && isSchemeTailRune(runes[end])) {
            end += 1
        }
        if (end < runes.size && runes[end] == r':') {
            let scheme = substring(pos, end)
            pos = end + 1
            return Some(scheme)
        }
        return None
    }

    private static func isSchemeTailRune(r: Rune): Bool {
        return isAlpha(r) || isDigit(r) || r == r'+' || r == r'-' || r == r'.'
    }

    private func consumePrefix(pfx: String): Bool {
        let pr = pfx.toRuneArray()
        if (pos + pr.size > runes.size) {
            return false
        }
        for (i in 0..pr.size) {
            if (runes[pos + i] != pr[i]) {
                return false
            }
        }
        pos += pr.size
        return true
    }

    private func consume(r: Rune): Bool {
        if (pos < runes.size && runes[pos] == r) {
            pos += 1
            return true
        }
        return false
    }

    private func takeUntilAny(stopChars: String): String {
        let stops = stopChars.toRuneArray()
        let start = pos
        while (pos < runes.size && !containsRune(stops, runes[pos])) {
            pos += 1
        }
        return substring(start, pos)
    }

    private static func containsRune(stops: Array<Rune>, r: Rune): Bool {
        for (s in stops) {
            if (r == s) {
                return true
            }
        }
        return false
    }

    private func remaining(): String {
        return substring(pos, runes.size)
    }

    private func substring(lo: Int64, hi: Int64): String {
        let sb = StringBuilder()
        for (i in lo..hi) {
            sb.append(runes[i])
        }
        return sb.toString()
    }

    private static func isAlpha(r: Rune): Bool {
        return (r >= r'A' && r <= r'Z') || (r >= r'a' && r <= r'z')
    }

    private static func isDigit(r: Rune): Bool {
        return r >= r'0' && r <= r'9'
    }
}
