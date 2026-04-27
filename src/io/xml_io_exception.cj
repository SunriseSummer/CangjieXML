package tinyxml2.io

import tinyxml2.error.*

/**
 * IO 期异常——读取 / 写入失败时抛出，携带一个 `XmlError`。
 *
 * 与 `XmlParseException` 的关系：
 * - `XmlParseException`：**语法**层面的错误（已经读到字节，但 XML 不合法）。
 * - `XmlIoException`：**IO 层面**的错误（找不到文件、磁盘写入失败、UTF-8 非法等）。
 *
 * 两者互不嵌套——`loadXmlFromFile` 读到字节后内部用 `parseXml`，语法错误
 * 仍然以 `XmlParseException` 原样抛出；`XmlIoException` 只负责 IO 边界。
 */
public class XmlIoException <: Exception {
    public let error: XmlError

    public init(error: XmlError) {
        super(error.toString())
        this.error = error
    }

    public override func getClassName(): String {
        "XmlIoException"
    }
}
