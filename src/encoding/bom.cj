/*
 * encoding — BOM 探测
 *
 * 对应 libxml2: encoding.c 中 xmlDetectCharEncoding 的字节探测部分。
 */
package cangjie_xml.encoding

/**
 * 从字节流开头探测 BOM。输入至少提供 `min(bytes.size, 4)` 字节即可决断。
 * 返回 `None` 表示没有 BOM。
 */
public func detectBom(bytes: Array<Byte>): ?BomKind {
    return detectBomAt(bytes, 0)
}

public func detectBomAt(bytes: Array<Byte>, offset: Int64): ?BomKind {
    let n = bytes.size - offset
    if (n <= 0) {
        return None
    }
    // UTF-32 BOM 必须优先于 UTF-16 检测（UTF-32 LE 的 FF FE 00 00 前两字节与
    // UTF-16 LE 的 FF FE 完全重合）。
    if (n >= 4) {
        if (bytes[offset] == 0xFFu8 && bytes[offset + 1] == 0xFEu8 &&
            bytes[offset + 2] == 0x00u8 && bytes[offset + 3] == 0x00u8) {
            return Some(BomKind.Utf32Le)
        }
        if (bytes[offset] == 0x00u8 && bytes[offset + 1] == 0x00u8 &&
            bytes[offset + 2] == 0xFEu8 && bytes[offset + 3] == 0xFFu8) {
            return Some(BomKind.Utf32Be)
        }
    }
    if (n >= 3 && bytes[offset] == 0xEFu8 && bytes[offset + 1] == 0xBBu8 && bytes[offset + 2] == 0xBFu8) {
        return Some(BomKind.Utf8)
    }
    if (n >= 2) {
        if (bytes[offset] == 0xFFu8 && bytes[offset + 1] == 0xFEu8) {
            return Some(BomKind.Utf16Le)
        }
        if (bytes[offset] == 0xFEu8 && bytes[offset + 1] == 0xFFu8) {
            return Some(BomKind.Utf16Be)
        }
    }
    return None
}

/**
 * 基于首字节启发式：当无 BOM 时，通过首四字节与 `<?xml` 的对齐模式推测字节序。
 * 失败时返回 `None`，调用方应回落到 UTF-8 或显式声明的编码。
 *
 * 对应 W3C XML §F 附录 "Autodetection of Character Encodings"。
 */
public func heuristicDetect(bytes: Array<Byte>): ?BomKind {
    if (bytes.size < 4) {
        return None
    }
    // 00 00 00 3C  →  UCS-4 BE (≈ UTF-32 BE)
    if (bytes[0] == 0x00u8 && bytes[1] == 0x00u8 && bytes[2] == 0x00u8 && bytes[3] == 0x3Cu8) {
        return Some(BomKind.Utf32Be)
    }
    // 3C 00 00 00  →  UCS-4 LE
    if (bytes[0] == 0x3Cu8 && bytes[1] == 0x00u8 && bytes[2] == 0x00u8 && bytes[3] == 0x00u8) {
        return Some(BomKind.Utf32Le)
    }
    // 00 3C 00 3F  →  UTF-16 BE（"<?" 各占两字节）
    if (bytes[0] == 0x00u8 && bytes[1] == 0x3Cu8 && bytes[2] == 0x00u8 && bytes[3] == 0x3Fu8) {
        return Some(BomKind.Utf16Be)
    }
    // 3C 00 3F 00  →  UTF-16 LE
    if (bytes[0] == 0x3Cu8 && bytes[1] == 0x00u8 && bytes[2] == 0x3Fu8 && bytes[3] == 0x00u8) {
        return Some(BomKind.Utf16Le)
    }
    // 3C 3F 78 6D  →  "<?xm" ASCII → UTF-8 / ISO-8859-*（此处不区分，由声明决定）
    return None
}
