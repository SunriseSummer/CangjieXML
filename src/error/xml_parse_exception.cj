package cangjie_xml.error

/**
 * 解析期异常——携带一个 `XmlError`，便于调用方按枚举分支处理。
 *
 * 与 `XmlException`（程序员错误）区分：`XmlParseException` 是**可预期的运行时故障**，
 * 调用方应捕获。之所以仍采用异常而非 `Result<T, E>`：
 *
 * - 仓颉语言的异常与模式匹配已足够胜任；
 * - 避免每层解析函数都显式传递 Result，简化内部实现；
 * - 外层 `parseString` 一点捕获即可。
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
