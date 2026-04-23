/*
 * core — 限定名（QName）
 *
 * 对应 libxml2 中通过 `xmlNs*` 与名字拼接实现的命名空间限定名。
 * CangjieXML 把它抽象为不可变 `struct`，比较走三元组语义（prefix 不参与），
 * 避免 libxml2 中 `prefix:localname` 字符串反复解析的重做开销。
 */
package cangjie_xml.core

/**
 * 限定名：`localName` 为本地名（必须是合法 `NCName`），`prefix` 为可选前缀，
 * `uri` 为命名空间 URI（未绑定命名空间时为 `None`）。
 *
 * 语义相等以 `(localName, uri)` 为准——两份 QName 只要本地名与命名空间 URI
 * 相同即视为同一个名字，与前缀写法无关。这符合 Namespaces in XML 1.0 §2.3。
 */
public struct QName <: Equatable<QName> & Hashable & ToString {
    public let localName: String
    public let prefix: ?String
    public let uri: ?String

    public init(localName: String, prefix!: ?String = None, uri!: ?String = None) {
        this.localName = localName
        this.prefix = prefix
        this.uri = uri
    }

    /** 无命名空间的简单名。 */
    public static func of(localName: String): QName {
        return QName(localName)
    }

    /** 从 `prefix:localName` 形式的字符串解析出 QName（不设置 uri）。 */
    public static func fromLexical(name: String): QName {
        match (name.indexOf(":")) {
            case Some(idx) =>
                let p = name[0..idx]
                let ln = name[idx + 1..name.size]
                return QName(ln, prefix: Some(p))
            case None => return QName(name)
        }
    }

    /** 在当前名字基础上绑定命名空间 URI，返回新实例。 */
    public func withUri(ns: ?String): QName {
        return QName(this.localName, prefix: this.prefix, uri: ns)
    }

    /** 在当前名字基础上替换 `prefix`，返回新实例。 */
    public func withPrefix(p: ?String): QName {
        return QName(this.localName, prefix: p, uri: this.uri)
    }

    /** 词法形态 `prefix:localName`（prefix 为 None 时仅返回 localName）。 */
    public func lexical(): String {
        match (prefix) {
            case Some(p) => return "${p}:${localName}"
            case None => return localName
        }
    }

    /** 扩展形态 `{uri}localName`（uri 为 None 时仅返回 localName）。 */
    public func expanded(): String {
        match (uri) {
            case Some(u) => return "{${u}}${localName}"
            case None => return localName
        }
    }

    public operator func ==(that: QName): Bool {
        return this.localName == that.localName && this.uri == that.uri
    }

    public operator func !=(that: QName): Bool {
        return !(this == that)
    }

    public func hashCode(): Int64 {
        let localHash = localName.hashCode()
        match (uri) {
            case Some(u) => return combineHash(localHash, u.hashCode())
            case None => return combineHash(localHash, 0)
        }
    }

    public func toString(): String {
        return expanded()
    }
}

/** 混合两个哈希值。使用 wrapping 乘法以避免 Int64 溢出。 */
func combineHash(a: Int64, b: Int64): Int64 {
    // 使用 XOR + 位旋转，避免 `*` 操作符默认的溢出检查。
    let shifted = (a << 5) | (a >> 59)
    return (shifted ^ a ^ b) & 0x7FFFFFFFFFFFFFFF
}
