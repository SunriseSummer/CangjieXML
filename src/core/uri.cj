/*
 * core — URI（RFC 3986）
 *
 * 对应 libxml2: uri.c
 *
 * 实现严格的 RFC 3986 解析与归一化，并提供相对参考解析（§5）。
 * 不依赖网络库；仅字符串级工作。
 */
package cangjie_xml.core

/**
 * 不可变 URI 值对象。字段语义与 RFC 3986 §3 一致：
 *
 *   URI = scheme ":" hier-part [ "?" query ] [ "#" fragment ]
 *   hier-part = "//" authority path-abempty
 *             | path-absolute / path-rootless / path-empty
 */
public struct Uri <: Equatable<Uri> & ToString {
    public let scheme: ?String
    public let authority: ?String
    public let path: String
    public let query: ?String
    public let fragment: ?String

    public init(
        scheme!: ?String,
        authority!: ?String,
        path!: String,
        query!: ?String,
        fragment!: ?String
    ) {
        this.scheme = scheme
        this.authority = authority
        this.path = path
        this.query = query
        this.fragment = fragment
    }

    /**
     * 解析 URI 或 URI-reference。失败时抛出 `XmlException(UriError)`。
     * 解析规则遵循 RFC 3986 附录 A ABNF。
     */
    public static func parse(s: String): Uri {
        return UriParser(s).run()
    }

    /** 解析失败返回 `None` 的变体。 */
    public static func tryParse(s: String): ?Uri {
        try {
            return Some(UriParser(s).run())
        } catch (_: XmlException) {
            return None
        }
    }

    /** 是否为绝对 URI（具有 scheme）。 */
    public func isAbsolute(): Bool {
        match (scheme) {
            case Some(_) => return true
            case None => return false
        }
    }

    /** 归一化：按 RFC 3986 §6 统一 scheme / authority 大小写、去除点段路径、解码非必要百分号。 */
    public func normalize(): Uri {
        let normScheme = match (scheme) {
            case Some(sch) => Some(sch.toAsciiLower())
            case None => None<String>
        }
        let normAuthority = match (authority) {
            case Some(a) => Some(normalizeAuthority(a))
            case None => None<String>
        }
        let normPath = removeDotSegments(path)
        return Uri(
            scheme: normScheme,
            authority: normAuthority,
            path: normPath,
            query: query,
            fragment: fragment
        )
    }

    /**
     * 以 `base` 为基，按 RFC 3986 §5.3 进行相对参考解析。
     * `this` 视作 reference，`base` 必须是绝对 URI。
     */
    public func resolve(base: Uri): Uri {
        if (!base.isAbsolute()) {
            throw XmlException(XmlError.UriError("base URI must be absolute: ${base}"))
        }
        if (this.isAbsolute()) {
            return this.normalize()
        }
        // RFC 3986 §5.2.2 Transform References
        var tScheme: ?String
        var tAuthority: ?String
        var tPath: String
        var tQuery: ?String
        if (this.authority.isSome()) {
            tAuthority = this.authority
            tPath = removeDotSegments(this.path)
            tQuery = this.query
            tScheme = base.scheme
        } else {
            if (this.path.isEmpty()) {
                tPath = base.path
                tQuery = match (this.query) {
                    case Some(q) => Some(q)
                    case None => base.query
                }
            } else {
                if (this.path.startsWith("/")) {
                    tPath = removeDotSegments(this.path)
                } else {
                    tPath = removeDotSegments(mergePaths(base, this.path))
                }
                tQuery = this.query
            }
            tAuthority = base.authority
            tScheme = base.scheme
        }
        return Uri(
            scheme: tScheme,
            authority: tAuthority,
            path: tPath,
            query: tQuery,
            fragment: this.fragment
        )
    }

    public operator func ==(that: Uri): Bool {
        return this.scheme == that.scheme && this.authority == that.authority && this.path == that.path && this.query == that
            .query && this.fragment == that.fragment
    }

    public operator func !=(that: Uri): Bool {
        return !(this == that)
    }

    /** 按 RFC 3986 §5.3 Component Recomposition 还原为字符串。 */
    public func toString(): String {
        let sb = StringBuilder()
        match (scheme) {
            case Some(s) =>
                sb.append(s)
                sb.append(":")
            case None => ()
        }
        match (authority) {
            case Some(a) =>
                sb.append("//")
                sb.append(a)
            case None => ()
        }
        sb.append(path)
        match (query) {
            case Some(q) =>
                sb.append("?")
                sb.append(q)
            case None => ()
        }
        match (fragment) {
            case Some(f) =>
                sb.append("#")
                sb.append(f)
            case None => ()
        }
        return sb.toString()
    }
}

/* ---------- 私有解析与归一化工具 ---------- */

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
    // 严格按 RFC 3986 §5.2.4 的状态机实现，避免误把 "./" 前缀认作空段。
    var remaining = input
    let out = StringBuilder()
    while (!remaining.isEmpty()) {
        if (remaining.startsWith("../")) {
            remaining = remaining[3..remaining.size]
        } else if (remaining.startsWith("./")) {
            remaining = remaining[2..remaining.size]
        } else if (remaining.startsWith("/./")) {
            remaining = "/" + remaining[3..remaining.size]
        } else if (remaining == "/.") {
            remaining = "/"
        } else if (remaining.startsWith("/../")) {
            remaining = "/" + remaining[4..remaining.size]
            popLastSegment(out)
        } else if (remaining == "/..") {
            remaining = "/"
            popLastSegment(out)
        } else if (remaining == "." || remaining == "..") {
            remaining = ""
        } else {
            // 移动第一段（含前导 "/"）到 out
            var pos = 0
            if (remaining[pos..pos + 1] == "/") {
                pos = 1
            }
            while (pos < remaining.size && remaining[pos..pos + 1] != "/") {
                pos += 1
            }
            out.append(remaining[0..pos])
            remaining = remaining[pos..remaining.size]
        }
    }
    return out.toString()
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
    var userinfo: ?String = None
    var hostAndPort = authority
    match (authority.indexOf("@")) {
        case Some(idx) =>
            userinfo = Some(authority[0..idx])
            hostAndPort = authority[idx + 1..authority.size]
        case None => ()
    }
    var host = hostAndPort
    var port: ?String = None
    // IPv6 字面量以 '[' 开头，':' 只有在 ']' 之后才是端口分隔符
    if (hostAndPort.startsWith("[")) {
        match (hostAndPort.indexOf("]")) {
            case Some(rb) =>
                host = hostAndPort[0..rb + 1]
                if (rb + 1 < hostAndPort.size && hostAndPort[rb + 1..rb + 2] == ":") {
                    port = Some(hostAndPort[rb + 2..hostAndPort.size])
                }
            case None => ()
        }
    } else {
        match (hostAndPort.lastIndexOf(":")) {
            case Some(idx) =>
                host = hostAndPort[0..idx]
                port = Some(hostAndPort[idx + 1..hostAndPort.size])
            case None => ()
        }
    }
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
        var authority: ?String = None
        var path: String
        if (consumePrefix("//")) {
            authority = Some(takeUntilAny("/?#"))
            path = takeUntilAny("?#")
        } else {
            path = takeUntilAny("?#")
        }
        var query: ?String = None
        if (consume(r'?')) {
            query = Some(takeUntilAny("#"))
        }
        var fragment: ?String = None
        if (consume(r'#')) {
            fragment = Some(remaining())
            pos = runes.size
        }
        if (pos != runes.size) {
            throw XmlException(XmlError.UriError("unexpected trailing characters in URI: ${input}"))
        }
        return Uri(scheme: scheme, authority: authority, path: path, query: query, fragment: fragment)
    }

    /** 尝试解析 scheme 部分（ALPHA *(ALPHA / DIGIT / "+" / "-" / ".")）。 */
    func tryParseScheme(): ?String {
        if (pos >= runes.size) {
            return None
        }
        let first = runes[pos]
        if (!isAlpha(first)) {
            return None
        }
        var end = pos + 1
        while (end < runes.size) {
            let r = runes[end]
            if (isAlpha(r) || isDigit(r) || r == r'+' || r == r'-' || r == r'.') {
                end += 1
            } else {
                break
            }
        }
        if (end < runes.size && runes[end] == r':') {
            let scheme = substring(pos, end)
            pos = end + 1
            return Some(scheme)
        }
        return None
    }

    func consumePrefix(pfx: String): Bool {
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

    func consume(r: Rune): Bool {
        if (pos < runes.size && runes[pos] == r) {
            pos += 1
            return true
        }
        return false
    }

    func takeUntilAny(stopChars: String): String {
        let stops = stopChars.toRuneArray()
        let start = pos
        while (pos < runes.size) {
            let cur = runes[pos]
            var found = false
            for (s in stops) {
                if (cur == s) {
                    found = true
                    break
                }
            }
            if (found) {
                break
            }
            pos += 1
        }
        return substring(start, pos)
    }

    func remaining(): String {
        return substring(pos, runes.size)
    }

    func substring(lo: Int64, hi: Int64): String {
        let sb = StringBuilder()
        for (i in lo..hi) {
            sb.append(runes[i])
        }
        return sb.toString()
    }

    func isAlpha(r: Rune): Bool {
        return (r >= r'A' && r <= r'Z') || (r >= r'a' && r <= r'z')
    }

    func isDigit(r: Rune): Bool {
        return r >= r'0' && r <= r'9'
    }
}
