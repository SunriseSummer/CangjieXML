/*
 * encoding — 单字节字符集
 *
 * 对应 libxml2: encoding.c 中 US-ASCII、ISO-8859-1..15 解码。
 *
 * 统一抽象为 `SingleByteDecoder` / `SingleByteEncoder`：
 *  - 低 128（0x00..0x7F）字节一律作 US-ASCII；
 *  - 高 128（0x80..0xFF）字节按具体编码的 128 项 `Array<Int32>` 映射表查表；
 *  - 映射表中 `-1` 表示"未定义"，解码时报 `InvalidBytes`。
 *
 * 每种具体编码都提供静态工厂函数。
 */
package cangjie_xml.encoding

import cangjie_xml.core.*

/** 通用单字节解码器。 */
public class SingleByteDecoder <: Decoder {
    private let nm: String
    // 长度 128：索引 i 对应字节值 0x80 + i 的 Unicode 码点；-1 表示未定义。
    private let highTable: Array<Int32>

    public init(name: String, highTable: Array<Int32>) {
        if (highTable.size != 128) {
            throw IllegalArgumentException("highTable must have length 128")
        }
        this.nm = name
        this.highTable = highTable
    }

    public prop name: String {
        get() {
            return nm
        }
    }

    public override func decode(bytes: Array<Byte>, start: Int64, end: Int64, endOfInput: Bool): DecodeResult {
        let _ = endOfInput // 单字节解码无跨片状态
        let sb = StringBuilder()
        var i = start
        while (i < end) {
            let b = UInt32(bytes[i])
            if (b < 0x80u32) {
                sb.append(Rune(b))
            } else {
                let cp = highTable[Int64(b - 0x80u32)]
                if (cp < 0) {
                    return DecodeResult(sb.toString(), i - start, DecodeStatus.InvalidBytes(i))
                }
                sb.append(Rune(UInt32(cp)))
            }
            i += 1
        }
        return DecodeResult(sb.toString(), end - start, DecodeStatus.Success)
    }
}

/** 通用单字节编码器。 */
public class SingleByteEncoder <: Encoder {
    private let nm: String
    // 反向表：给定高 128 码点区段？太大。采用线性扫 + 小哈希折衷：
    // 存一份 (code point -> byte) 的 ArrayList，顺序由 highTable 决定。
    private let highToByte: Array<Int32> // 长度 128；[i] 是高字节 i 代表的码点（与 Decoder 共享）

    public init(name: String, highTable: Array<Int32>) {
        if (highTable.size != 128) {
            throw IllegalArgumentException("highTable must have length 128")
        }
        this.nm = name
        this.highToByte = highTable
    }

    public prop name: String {
        get() {
            return nm
        }
    }

    public override func encode(text: String): EncodeResult {
        let runes = text.toRuneArray()
        let out = GrowableBuffer()
        for (i in 0..runes.size) {
            let cp = Int32(UInt32(runes[i]))
            if (cp < 0x80) {
                out.writeByte(UInt8(cp))
                continue
            }
            // 线性扫高表查反向映射
            var found = false
            for (k in 0..128) {
                if (highToByte[k] == cp) {
                    out.writeByte(UInt8(0x80u32 + UInt32(k)))
                    found = true
                    break
                }
            }
            if (!found) {
                return EncodeResult(out.toBytes(), EncodeStatus.Unmappable(i, cp))
            }
        }
        return EncodeResult(out.toBytes(), EncodeStatus.Success)
    }
}

/* ---------- 映射表 ---------- */

/** US-ASCII：0x80..0xFF 全部未定义。 */
public func asciiHighTable(): Array<Int32> {
    let t = Array<Int32>(128, repeat: -1i32)
    return t
}

/** ISO-8859-1（Latin-1）：高 128 字节直接等于其字节值（恒等映射到 U+0080..U+00FF）。 */
public func iso88591HighTable(): Array<Int32> {
    let t = Array<Int32>(128, repeat: 0i32)
    for (i in 0..128) {
        t[i] = Int32(0x80 + i)
    }
    return t
}

/**
 * 构造 ISO-8859-x 映射表：输入 `diffs` 为"与 ISO-8859-1 不同的条目"，
 * 每条 `(highIndex, codePoint)`；未出现的高字节沿用 ISO-8859-1。
 */
func iso8859Variant(diffs: Array<(Int64, Int32)>): Array<Int32> {
    let t = iso88591HighTable()
    for (i in 0..diffs.size) {
        let (idx, cp) = diffs[i]
        t[idx] = cp
    }
    return t
}

/* 下列高字节差异表源自 Unicode.org 的 8859-x.TXT 映射文件（仅记差异）。 */

/** ISO-8859-2（Latin-2，中欧）。 */
public func iso88592HighTable(): Array<Int32> {
    return iso8859Variant([
        (0x21, 0x0104i32), (0x22, 0x02D8i32), (0x23, 0x0141i32), (0x25, 0x013Di32),
        (0x26, 0x015Ai32), (0x29, 0x0160i32), (0x2A, 0x015Ei32), (0x2B, 0x0164i32),
        (0x2C, 0x0179i32), (0x2E, 0x017Di32), (0x2F, 0x017Bi32), (0x31, 0x0105i32),
        (0x32, 0x02DBi32), (0x33, 0x0142i32), (0x35, 0x013Ei32), (0x36, 0x015Bi32),
        (0x37, 0x02C7i32), (0x39, 0x0161i32), (0x3A, 0x015Fi32), (0x3B, 0x0165i32),
        (0x3C, 0x017Ai32), (0x3D, 0x02DDi32), (0x3E, 0x017Ei32), (0x3F, 0x017Ci32),
        (0x40, 0x0154i32), (0x43, 0x0102i32), (0x45, 0x0139i32), (0x46, 0x0106i32),
        (0x48, 0x010Ci32), (0x4A, 0x0118i32), (0x4C, 0x011Ai32), (0x4F, 0x010Ei32),
        (0x50, 0x0110i32), (0x51, 0x0143i32), (0x52, 0x0147i32), (0x55, 0x0150i32),
        (0x58, 0x0158i32), (0x59, 0x016Ei32), (0x5B, 0x0170i32), (0x5E, 0x0162i32),
        (0x60, 0x0155i32), (0x63, 0x0103i32), (0x65, 0x013Ai32), (0x66, 0x0107i32),
        (0x68, 0x010Di32), (0x6A, 0x0119i32), (0x6C, 0x011Bi32), (0x6F, 0x010Fi32),
        (0x70, 0x0111i32), (0x71, 0x0144i32), (0x72, 0x0148i32), (0x75, 0x0151i32),
        (0x78, 0x0159i32), (0x79, 0x016Fi32), (0x7B, 0x0171i32), (0x7E, 0x0163i32),
        (0x7F, 0x02D9i32)
    ])
}

/** ISO-8859-3（Latin-3，南欧）。仅包含已定义字符的差异；未定义位置留 -1。 */
public func iso88593HighTable(): Array<Int32> {
    var t = iso88591HighTable()
    // 先把 8859-3 中未定义的 0xA5/0xAE/0xBE/0xC3/0xD0/0xE3/0xF0 等标 -1
    let undefinedHi: Array<Int64> = [0x25, 0x2E, 0x3E, 0x43, 0x50, 0x63, 0x70]
    for (i in 0..undefinedHi.size) {
        t[undefinedHi[i]] = -1i32
    }
    let diffs: Array<(Int64, Int32)> = [
        (0x21, 0x0126i32), (0x22, 0x02D8i32), (0x26, 0x0124i32), (0x29, 0x0130i32),
        (0x2A, 0x015Ei32), (0x2B, 0x011Ei32), (0x2C, 0x0134i32), (0x2F, 0x017Bi32),
        (0x31, 0x0127i32), (0x36, 0x0125i32), (0x39, 0x0131i32), (0x3A, 0x015Fi32),
        (0x3B, 0x011Fi32), (0x3C, 0x0135i32), (0x3D, 0x00BDi32), (0x3F, 0x017Ci32),
        (0x45, 0x010Ai32), (0x46, 0x0108i32), (0x55, 0x0120i32), (0x58, 0x011Ci32),
        (0x5D, 0x016Ci32), (0x5E, 0x015Ci32), (0x65, 0x010Bi32), (0x66, 0x0109i32),
        (0x75, 0x0121i32), (0x78, 0x011Di32), (0x7D, 0x016Di32), (0x7E, 0x015Di32),
        (0x7F, 0x02D9i32)
    ]
    for (i in 0..diffs.size) {
        let (idx, cp) = diffs[i]
        t[idx] = cp
    }
    return t
}

/** ISO-8859-4（Latin-4，北欧）。 */
public func iso88594HighTable(): Array<Int32> {
    return iso8859Variant([
        (0x21, 0x0104i32), (0x22, 0x0138i32), (0x23, 0x0156i32), (0x25, 0x0128i32), (0x26, 0x013Bi32),
        (0x29, 0x0160i32), (0x2A, 0x0112i32), (0x2B, 0x0122i32), (0x2C, 0x0166i32), (0x2E, 0x017Di32),
        (0x31, 0x0105i32), (0x32, 0x02DBi32), (0x33, 0x0157i32), (0x35, 0x0129i32), (0x36, 0x013Ci32),
        (0x37, 0x02C7i32), (0x39, 0x0161i32), (0x3A, 0x0113i32), (0x3B, 0x0123i32), (0x3C, 0x0167i32),
        (0x3D, 0x014Ai32), (0x3E, 0x017Ei32), (0x3F, 0x014Bi32), (0x40, 0x0100i32), (0x47, 0x012Ei32),
        (0x48, 0x010Ci32), (0x4A, 0x0118i32), (0x4C, 0x0116i32), (0x4F, 0x012Ai32), (0x50, 0x0110i32),
        (0x51, 0x0145i32), (0x52, 0x014Ci32), (0x53, 0x0136i32), (0x59, 0x0172i32), (0x5D, 0x0168i32),
        (0x5E, 0x016Ai32), (0x60, 0x0101i32), (0x67, 0x012Fi32), (0x68, 0x010Di32), (0x6A, 0x0119i32),
        (0x6C, 0x0117i32), (0x6F, 0x012Bi32), (0x70, 0x0111i32), (0x71, 0x0146i32), (0x72, 0x014Di32),
        (0x73, 0x0137i32), (0x79, 0x0173i32), (0x7D, 0x0169i32), (0x7E, 0x016Bi32), (0x7F, 0x02D9i32)
    ])
}

/** ISO-8859-5（斯拉夫字母）。 */
public func iso88595HighTable(): Array<Int32> {
    let t = Array<Int32>(128, repeat: 0i32)
    // 00..1F 同 Latin-1
    for (i in 0..0x21) {
        t[i] = Int32(0x80 + i)
    }
    // A1..AC => U+0401..U+040C
    for (i in 0..12) {
        t[0x21 + i] = Int32(0x0401 + i)
    }
    t[0x2D] = 0x00ADi32 // SHY
    // AE..AF => 040E..040F
    t[0x2E] = 0x040Ei32
    t[0x2F] = 0x040Fi32
    // B0..EF => 0410..044F
    for (i in 0..64) {
        t[0x30 + i] = Int32(0x0410 + i)
    }
    // F0 => 2116 NUMERO SIGN
    t[0x70] = 0x2116i32
    // F1..FC => 0451..045C
    for (i in 0..12) {
        t[0x71 + i] = Int32(0x0451 + i)
    }
    t[0x7D] = 0x00A7i32 // SECTION SIGN
    t[0x7E] = 0x045Ei32
    t[0x7F] = 0x045Fi32
    return t
}

/** ISO-8859-9（Latin-5，土耳其）。仅 6 处差异。 */
public func iso88599HighTable(): Array<Int32> {
    return iso8859Variant([
        (0x50, 0x011Ei32), // 0xD0 LATIN CAPITAL LETTER G WITH BREVE
        (0x5D, 0x0130i32), // 0xDD LATIN CAPITAL LETTER I WITH DOT ABOVE
        (0x5E, 0x015Ei32), // 0xDE LATIN CAPITAL LETTER S WITH CEDILLA
        (0x70, 0x011Fi32), // 0xF0 LATIN SMALL LETTER G WITH BREVE
        (0x7D, 0x0131i32), // 0xFD LATIN SMALL LETTER DOTLESS I
        (0x7E, 0x015Fi32)  // 0xFE LATIN SMALL LETTER S WITH CEDILLA
    ])
}

/** ISO-8859-15（Latin-9，含欧元符号）。与 Latin-1 仅 8 处差异。 */
public func iso885915HighTable(): Array<Int32> {
    return iso8859Variant([
        (0x24, 0x20ACi32), // 0xA4 EURO SIGN
        (0x26, 0x0160i32), // 0xA6 S caron
        (0x28, 0x0161i32), // 0xA8 s caron
        (0x34, 0x017Di32), // 0xB4 Z caron
        (0x38, 0x017Ei32), // 0xB8 z caron
        (0x3C, 0x0152i32), // 0xBC OE
        (0x3D, 0x0153i32), // 0xBD oe
        (0x3E, 0x0178i32)  // 0xBE Y diaeresis
    ])
}

/* ---------- 便利工厂 ---------- */

public func asciiDecoder(): SingleByteDecoder {
    return SingleByteDecoder("us-ascii", asciiHighTable())
}

public func asciiEncoder(): SingleByteEncoder {
    return SingleByteEncoder("us-ascii", asciiHighTable())
}

public func iso88591Decoder(): SingleByteDecoder {
    return SingleByteDecoder("iso-8859-1", iso88591HighTable())
}

public func iso88591Encoder(): SingleByteEncoder {
    return SingleByteEncoder("iso-8859-1", iso88591HighTable())
}

public func iso88592Decoder(): SingleByteDecoder {
    return SingleByteDecoder("iso-8859-2", iso88592HighTable())
}

public func iso88592Encoder(): SingleByteEncoder {
    return SingleByteEncoder("iso-8859-2", iso88592HighTable())
}

public func iso88593Decoder(): SingleByteDecoder {
    return SingleByteDecoder("iso-8859-3", iso88593HighTable())
}

public func iso88594Decoder(): SingleByteDecoder {
    return SingleByteDecoder("iso-8859-4", iso88594HighTable())
}

public func iso88595Decoder(): SingleByteDecoder {
    return SingleByteDecoder("iso-8859-5", iso88595HighTable())
}

public func iso88599Decoder(): SingleByteDecoder {
    return SingleByteDecoder("iso-8859-9", iso88599HighTable())
}

public func iso885915Decoder(): SingleByteDecoder {
    return SingleByteDecoder("iso-8859-15", iso885915HighTable())
}

public func iso885915Encoder(): SingleByteEncoder {
    return SingleByteEncoder("iso-8859-15", iso885915HighTable())
}
