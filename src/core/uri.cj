/*
 * core — URI（RFC 3986）：值对象定义
 *
 * 对应 libxml2: uri.c
 *
 * 实现严格的 RFC 3986 解析与归一化，并提供相对参考解析（§5）。
 * 不依赖网络库；仅字符串级工作。
 *
 * 为保持单个源文件 ≤ 300 行，实现按关注点拆分：
 *   - `uri.cj`          — `Uri` 结构体、构造、`==`/`!=`/`toString`/基本判断
 *   - `uri_resolve.cj`  — `normalize` / `resolve` 算法（RFC 3986 §5 / §6）
 *   - `uri_internals.cj`— `UriParser` 递归下降解析 + 归一化辅助函数
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

    public operator func ==(that: Uri): Bool {
        return this.scheme == that.scheme &&
            this.authority == that.authority &&
            this.path == that.path &&
            this.query == that.query &&
            this.fragment == that.fragment
    }

    public operator func !=(that: Uri): Bool {
        return !(this == that)
    }

    /** 按 RFC 3986 §5.3 Component Recomposition 还原为字符串。 */
    public func toString(): String {
        let sb = StringBuilder()
        appendSchemePart(sb)
        appendAuthorityPart(sb)
        sb.append(path)
        appendQueryPart(sb)
        appendFragmentPart(sb)
        return sb.toString()
    }

    private func appendSchemePart(sb: StringBuilder): Unit {
        match (scheme) {
            case Some(s) =>
                sb.append(s)
                sb.append(":")
            case None => ()
        }
    }

    private func appendAuthorityPart(sb: StringBuilder): Unit {
        match (authority) {
            case Some(a) =>
                sb.append("//")
                sb.append(a)
            case None => ()
        }
    }

    private func appendQueryPart(sb: StringBuilder): Unit {
        match (query) {
            case Some(q) =>
                sb.append("?")
                sb.append(q)
            case None => ()
        }
    }

    private func appendFragmentPart(sb: StringBuilder): Unit {
        match (fragment) {
            case Some(f) =>
                sb.append("#")
                sb.append(f)
            case None => ()
        }
    }
}
