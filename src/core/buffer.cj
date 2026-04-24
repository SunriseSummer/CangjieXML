/*
 * core — 缓冲区
 *
 * 对应 libxml2: buf.c
 *
 * 提供基于 `ArrayList<Byte>` 的可增长字节缓冲，以及封装了上限检查的
 * `BoundedBuffer` 装饰器，用于防御性解析场景（如属性值、实体展开长度限制）。
 */
package cangjie_xml.core

import std.collection.*

/**
 * 可增长字节缓冲：薄包装 `ArrayList<Byte>`，向外提供与 XML 解析/序列化对齐的 API。
 *
 * - 所有写入操作均追加到末尾；
 * - `toString` 将内容按 UTF-8 解码。若需其他编码，由 `encoding` 包解码后再写入。
 */
public class GrowableBuffer {
    private let data: ArrayList<Byte>

    public init() {
        this.data = ArrayList<Byte>()
    }

    public init(capacity: Int64) {
        this.data = ArrayList<Byte>(capacity)
    }

    /** 当前字节数。 */
    public prop size: Int64 {
        get() {
            return data.size
        }
    }

    public func isEmpty(): Bool {
        return data.isEmpty()
    }

    /** 清空缓冲，容量保留以便复用。 */
    public func clear(): Unit {
        data.clear()
    }

    /** 追加单个字节。 */
    public func writeByte(b: Byte): Unit {
        data.add(b)
    }

    /** 追加字节数组。 */
    public func writeBytes(bytes: Array<Byte>): Unit {
        for (b in bytes) {
            data.add(b)
        }
    }

    /** 追加字符串（以 UTF-8 编码）。 */
    public func writeString(s: String): Unit {
        writeBytes(s.toArray())
    }

    /** 追加一个 Unicode 码点（以 UTF-8 编码写入）。 */
    public func writeCodePoint(cp: Int32): Unit {
        let u = UInt32(cp)
        if (u < 0x80u32) {
            data.add(UInt8(u))
        } else if (u < 0x800u32) {
            data.add(UInt8(0xC0u32 | (u >> 6)))
            data.add(UInt8(0x80u32 | (u & 0x3Fu32)))
        } else if (u < 0x10000u32) {
            data.add(UInt8(0xE0u32 | (u >> 12)))
            data.add(UInt8(0x80u32 | ((u >> 6) & 0x3Fu32)))
            data.add(UInt8(0x80u32 | (u & 0x3Fu32)))
        } else {
            data.add(UInt8(0xF0u32 | (u >> 18)))
            data.add(UInt8(0x80u32 | ((u >> 12) & 0x3Fu32)))
            data.add(UInt8(0x80u32 | ((u >> 6) & 0x3Fu32)))
            data.add(UInt8(0x80u32 | (u & 0x3Fu32)))
        }
    }

    /** 快照当前字节内容（拷贝）。 */
    public func toBytes(): Array<Byte> {
        let out = Array<Byte>(data.size, repeat: 0u8)
        for (i in 0..data.size) {
            out[i] = data[i]
        }
        return out
    }

    /** 将内容按 UTF-8 解码为 `String`。非法字节序列将触发异常。 */
    public func toString(): String {
        return String.fromUtf8(toBytes())
    }
}

/**
 * 带上限的字节缓冲：在 `GrowableBuffer` 的基础上，每次写入时检查总字节数
 * 是否超出 `maxBytes`。超限时抛出 `XmlException`，携带错误码 `LimitExceeded`。
 *
 * 设计意图：在解析器层面拦截 Billion Laughs / 超长属性值等资源放大攻击。
 */
public class BoundedBuffer {
    private let inner: GrowableBuffer
    public let maxBytes: Int64

    public init(maxBytes!: Int64) {
        if (maxBytes <= 0) {
            throw IllegalArgumentException("maxBytes must be positive, got ${maxBytes}")
        }
        this.inner = GrowableBuffer()
        this.maxBytes = maxBytes
    }

    public prop size: Int64 {
        get() {
            return inner.size
        }
    }

    public func isEmpty(): Bool {
        return inner.isEmpty()
    }

    public func clear(): Unit {
        inner.clear()
    }

    private func ensureCapacity(extra: Int64): Unit {
        if (inner.size + extra > maxBytes) {
            throw XmlException(XmlError.LimitExceeded(Position.unknown(), "buffer would exceed ${maxBytes} bytes"))
        }
    }

    public func writeByte(b: Byte): Unit {
        ensureCapacity(1)
        inner.writeByte(b)
    }

    public func writeBytes(bytes: Array<Byte>): Unit {
        ensureCapacity(bytes.size)
        inner.writeBytes(bytes)
    }

    public func writeString(s: String): Unit {
        let bytes = s.toArray()
        ensureCapacity(bytes.size)
        inner.writeBytes(bytes)
    }

    public func writeCodePoint(cp: Int32): Unit {
        // UTF-8 最多 4 字节
        ensureCapacity(4)
        inner.writeCodePoint(cp)
    }

    public func toBytes(): Array<Byte> {
        return inner.toBytes()
    }

    public func toString(): String {
        return inner.toString()
    }
}
