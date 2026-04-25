package cangjie_xml.error

/**
 * 解析期异常——携带一个 `XmlError`，便于调用方按枚举分支处理。
 *
 * 与 `XmlException`（程序员错误）区分：`XmlParseException` 是**可预期的运行时
 * 故障**，调用方应捕获。
 */
public class XmlParseException <: Exception {
    public let error: XmlError

    public init(error: XmlError) {
        super(error.toString())
        this.error = error
    }

    public override func getClassName(): String {
        "XmlParseException"
    }
}
