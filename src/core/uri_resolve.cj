/*
 * core — URI 归一化与相对参考解析
 *
 * 拆自原 `uri.cj`：`normalize` / `resolve`。
 * `resolve` 按 RFC 3986 §5.2.2 拆为三个小函数，每个圈复杂度显著下降。
 */
package cangjie_xml.core

extend Uri {
    /** 归一化：按 RFC 3986 §6 统一 scheme / authority 大小写、去除点段路径。 */
    public func normalize(): Uri {
        return Uri(
            scheme: lowerAscii(scheme),
            authority: mapOpt(authority, normalizeAuthority),
            path: removeDotSegments(path),
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
        if (this.authority.isSome()) {
            return resolveWithAuthority(base)
        }
        return resolveWithoutAuthority(base)
    }

    private func resolveWithAuthority(base: Uri): Uri {
        return Uri(
            scheme: base.scheme,
            authority: this.authority,
            path: removeDotSegments(this.path),
            query: this.query,
            fragment: this.fragment
        )
    }

    private func resolveWithoutAuthority(base: Uri): Uri {
        let (tPath, tQuery) = computeResolvedPathAndQuery(base)
        return Uri(
            scheme: base.scheme,
            authority: base.authority,
            path: tPath,
            query: tQuery,
            fragment: this.fragment
        )
    }

    private func computeResolvedPathAndQuery(base: Uri): (String, ?String) {
        if (this.path.isEmpty()) {
            let q = match (this.query) {
                case Some(q) => Some(q)
                case None => base.query
            }
            return (base.path, q)
        }
        let p = if (this.path.startsWith("/")) {
            removeDotSegments(this.path)
        } else {
            removeDotSegments(mergePaths(base, this.path))
        }
        return (p, this.query)
    }
}

/* ---------- 私有通用工具 ---------- */

private func lowerAscii(s: ?String): ?String {
    match (s) {
        case Some(x) => return Some(x.toAsciiLower())
        case None => return None
    }
}

private func mapOpt(s: ?String, f: (String) -> String): ?String {
    match (s) {
        case Some(x) => return Some(f(x))
        case None => return None
    }
}
