/*
 * encoding — 编码注册表
 *
 * 对应 libxml2: encoding.c 的 xmlFindCharEncodingHandler / xmlAddEncodingAlias。
 *
 * 以别名 / 规范名映射为基础，支持：
 *   - 按字符串查找（大小写不敏感、`_` / `-` / 空格等价）；
 *   - 注册自定义编码的解码器工厂；
 *   - 枚举已知规范名。
 */
package cangjie_xml.encoding

import std.collection.*

/** 解码器工厂：每次调用返回一个带状态的全新实例。 */
public type DecoderFactory = () -> Decoder

/** 编码器工厂：同上。 */
public type EncoderFactory = () -> Encoder

/**
 * 编码注册表。线程语义：注册由构造时一次性完成；运行期只读的查询可安全并发调用。
 * 若需要动态注册，调用方自行加锁。
 */
public class EncodingRegistry {
    // 规范名 → 工厂
    private let decoders: HashMap<String, DecoderFactory>
    private let encoders: HashMap<String, EncoderFactory>
    // 归一化别名 → 规范名
    private let aliases: HashMap<String, String>

    public init() {
        this.decoders = HashMap<String, DecoderFactory>()
        this.encoders = HashMap<String, EncoderFactory>()
        this.aliases = HashMap<String, String>()
    }

    /** 注册一个规范名及其解码器工厂。 */
    public func registerDecoder(canonical: String, factory: DecoderFactory): Unit {
        let c = normalize(canonical)
        decoders.add(c, factory)
        aliases.add(c, c)
    }

    /** 注册一个规范名及其编码器工厂。 */
    public func registerEncoder(canonical: String, factory: EncoderFactory): Unit {
        let c = normalize(canonical)
        encoders.add(c, factory)
        aliases.add(c, c)
    }

    /** 注册别名 → 规范名映射（规范名须已注册）。 */
    public func registerAlias(alias: String, canonical: String): Unit {
        aliases.add(normalize(alias), normalize(canonical))
    }

    /** 获取解码器实例。名字不识别时返回 `None`。 */
    public func newDecoder(name: String): ?Decoder {
        match (aliases.get(normalize(name))) {
            case Some(canon) =>
                match (decoders.get(canon)) {
                    case Some(f) => return Some(f())
                    case None => return None
                }
            case None => return None
        }
    }

    /** 获取编码器实例。 */
    public func newEncoder(name: String): ?Encoder {
        match (aliases.get(normalize(name))) {
            case Some(canon) =>
                match (encoders.get(canon)) {
                    case Some(f) => return Some(f())
                    case None => return None
                }
            case None => return None
        }
    }

    /** 该名字是否可被解析（至少是已知别名）。 */
    public func isKnown(name: String): Bool {
        return aliases.contains(normalize(name))
    }

    /** 解析为规范名（若已知）。 */
    public func canonicalize(name: String): ?String {
        return aliases.get(normalize(name))
    }

    /**
     * 名字归一化：小写 + 去掉 `-` / `_` / 空格；"UTF-8" / "utf_8" / "utf8" 全部等价。
     */
    public static func normalize(name: String): String {
        let sb = StringBuilder()
        for (r in name.toRuneArray()) {
            if (r == r'-' || r == r'_' || r == r' ') {
                continue
            }
            let cp = UInt32(r)
            if (cp >= 0x41u32 && cp <= 0x5Au32) {
                sb.append(Rune(cp + 0x20u32))
            } else {
                sb.append(r)
            }
        }
        return sb.toString()
    }

    /** 构造一份已预注册所有内置编码的注册表。 */
    public static func defaultRegistry(): EncodingRegistry {
        let r = EncodingRegistry()

        // UTF-8
        r.registerDecoder("utf-8", { => Utf8Decoder() })
        r.registerEncoder("utf-8", { => Utf8Encoder() })
        r.registerAlias("utf8", "utf-8")

        // UTF-16 LE/BE
        r.registerDecoder("utf-16le", { => Utf16Decoder.littleEndian() })
        r.registerEncoder("utf-16le", { => Utf16Encoder.littleEndian() })
        r.registerDecoder("utf-16be", { => Utf16Decoder.bigEndian() })
        r.registerEncoder("utf-16be", { => Utf16Encoder.bigEndian() })
        // "utf-16" 按 XML 规范要求带 BOM；此处暂简化为 BE。实际由 BOM 探测覆盖。
        r.registerAlias("utf-16", "utf-16be")

        // UTF-32 LE/BE
        r.registerDecoder("utf-32le", { => Utf32Decoder.littleEndian() })
        r.registerDecoder("utf-32be", { => Utf32Decoder.bigEndian() })
        r.registerAlias("utf-32", "utf-32be")
        r.registerAlias("ucs-4", "utf-32be")
        r.registerAlias("ucs-4be", "utf-32be")
        r.registerAlias("ucs-4le", "utf-32le")

        // US-ASCII
        r.registerDecoder("us-ascii", { => asciiDecoder() })
        r.registerEncoder("us-ascii", { => asciiEncoder() })
        r.registerAlias("ascii", "us-ascii")
        r.registerAlias("ansi-x3.4-1968", "us-ascii")

        // ISO-8859-*
        r.registerDecoder("iso-8859-1", { => iso88591Decoder() })
        r.registerEncoder("iso-8859-1", { => iso88591Encoder() })
        r.registerAlias("latin-1", "iso-8859-1")
        r.registerAlias("latin1", "iso-8859-1")
        r.registerAlias("iso-latin-1", "iso-8859-1")

        r.registerDecoder("iso-8859-2", { => iso88592Decoder() })
        r.registerEncoder("iso-8859-2", { => iso88592Encoder() })
        r.registerAlias("latin-2", "iso-8859-2")

        r.registerDecoder("iso-8859-3", { => iso88593Decoder() })
        r.registerAlias("latin-3", "iso-8859-3")

        r.registerDecoder("iso-8859-4", { => iso88594Decoder() })
        r.registerAlias("latin-4", "iso-8859-4")

        r.registerDecoder("iso-8859-5", { => iso88595Decoder() })
        r.registerAlias("cyrillic", "iso-8859-5")

        r.registerDecoder("iso-8859-9", { => iso88599Decoder() })
        r.registerAlias("latin-5", "iso-8859-9")

        r.registerDecoder("iso-8859-15", { => iso885915Decoder() })
        r.registerEncoder("iso-8859-15", { => iso885915Encoder() })
        r.registerAlias("latin-9", "iso-8859-15")

        return r
    }
}
