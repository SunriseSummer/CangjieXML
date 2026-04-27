package tinyxml2.io

import std.fs.*
import tinyxml2.dom.*
import tinyxml2.error.*
import tinyxml2.parser.*

/**
 * 从文件加载 XML 文档——对 `parseXml` 的 IO 侧封装。
 *
 * 文件一律按 **UTF-8** 解读；XML 声明里的 `encoding="..."` 不参与实际解码。
 * IO 异常被收敛成 `XmlIoException`；语法错误仍以 `XmlParseException` 原样抛出。
 *
 * | 触发情形 | 抛出 |
 * |---|---|
 * | `path` 指向不存在的文件 | `XmlIoException(FileNotFound(path))` |
 * | 读取过程出现 `FSException` | `XmlIoException(FileReadFailed(path, cause))` |
 * | 字节不是合法 UTF-8 | `XmlIoException(FileReadFailed(path, "invalid UTF-8"))` |
 * | XML 语法错误 | `XmlParseException(...)`（原样抛出） |
 */
/** 错误消息里用来标识"无文件路径的字节源"。 */
const IN_MEMORY_SOURCE_LABEL: String = "<bytes>"

public func loadXmlFromFile(path: String): XmlDocument {
    loadXmlFromFile(path, XmlParseOptions.default_())
}

public func loadXmlFromFile(path: String, options: XmlParseOptions): XmlDocument {
    let bytes = readAllBytes(path)
    let text = decodeUtf8(bytes, path)
    parseXml(text, options)
}

/**
 * 从字节数组解析 XML 文档。字节按 UTF-8 解码；非法 UTF-8 抛 `XmlIoException`。
 *
 * 典型场景：HTTP 响应体、JDBC Blob、嵌入资源等"已经在内存里的字节流"。
 */
public func parseXmlBytes(bytes: Array<Byte>): XmlDocument {
    parseXmlBytes(bytes, XmlParseOptions.default_())
}

public func parseXmlBytes(bytes: Array<Byte>, options: XmlParseOptions): XmlDocument {
    // 使用 "<bytes>" 作为路径占位符，便于错误消息体现来源
    let text = decodeUtf8(bytes, IN_MEMORY_SOURCE_LABEL)
    parseXml(text, options)
}

// ======================================================================
// 内部工具
// ======================================================================

func readAllBytes(path: String): Array<Byte> {
    let p = Path(path)
    if (!exists(p)) {
        throw XmlIoException(FileNotFound(path))
    }
    try {
        File.readFrom(p)
    } catch (e: FSException) {
        throw XmlIoException(FileReadFailed(path, e.message))
    }
}

func decodeUtf8(bytes: Array<Byte>, source: String): String {
    try {
        String.fromUtf8(bytes)
    } catch (e: Exception) {
        throw XmlIoException(FileReadFailed(source, "invalid UTF-8: ${e.message}"))
    }
}
