package cangjie_xml.error

/**
 * CangjieXML 库统一的错误类型。
 *
 * 带上下文的枚举：每个分支携带定位与原因信息，调用方可直接做模式匹配处理。
 */
public enum XmlError <: ToString {
    /** DOM 手工构造时的非法操作（例如从空父节点移除）。 */
    | DomOperationFailed(String)
    /** 文件不存在。 */
    | FileNotFound(String)
    /** 文件读取失败：path, cause。 */
    | FileReadFailed(String, String)
    /** 文件写入失败：path, cause。 */
    | FileWriteFailed(String, String)
    /** 空文档。 */
    | EmptyDocument
    /** 起止标签不匹配：openTag, closeTag, at。 */
    | MismatchedElement(String, String, SourcePos)
    /** 非法属性：name, at, reason。 */
    | InvalidAttribute(String, SourcePos, String)
    /** 非法文本：at, reason。 */
    | InvalidText(SourcePos, String)
    /** 非法注释：at, reason。 */
    | InvalidComment(SourcePos, String)
    /** 非法 XML 声明：at, reason。 */
    | InvalidDeclaration(SourcePos, String)
    /** 非法未知节点：at, reason。 */
    | InvalidUnknownNode(SourcePos, String)
    /** 非法编码：at, reason。 */
    | InvalidEncoding(SourcePos, String)
    /** 元素嵌套深度超限：limit, at。 */
    | ElementDepthExceeded(Int64, SourcePos)
    /** 值编解码失败：targetType, text, at。 */
    | ValueDecodeFailed(String, String, SourcePos)

    public func toString(): String {
        match (this) {
            case DomOperationFailed(msg) => "DomOperationFailed: ${msg}"
            case FileNotFound(path) => "FileNotFound: ${path}"
            case FileReadFailed(path, cause) => "FileReadFailed: ${path} (${cause})"
            case FileWriteFailed(path, cause) => "FileWriteFailed: ${path} (${cause})"
            case EmptyDocument => "EmptyDocument"
            case MismatchedElement(o, c, p) => "MismatchedElement: <${o}> vs </${c}> at ${p}"
            case InvalidAttribute(n, p, r) => "InvalidAttribute '${n}' at ${p}: ${r}"
            case InvalidText(p, r) => "InvalidText at ${p}: ${r}"
            case InvalidComment(p, r) => "InvalidComment at ${p}: ${r}"
            case InvalidDeclaration(p, r) => "InvalidDeclaration at ${p}: ${r}"
            case InvalidUnknownNode(p, r) => "InvalidUnknownNode at ${p}: ${r}"
            case InvalidEncoding(p, r) => "InvalidEncoding at ${p}: ${r}"
            case ElementDepthExceeded(l, p) => "ElementDepthExceeded (limit=${l}) at ${p}"
            case ValueDecodeFailed(t, s, p) => "ValueDecodeFailed: cannot parse '${s}' as ${t} at ${p}"
        }
    }
}

/**
 * 当库内部不变量被破坏，或调用方明显误用 API 时抛出的异常。
 *
 * 与 `XmlError` 区分：
 * - `Option<T>`：可预期"无值"。
 * - `XmlError`：可预期"可能失败"，调用方应显式处理。
 * - `XmlException`：不可预期、程序员错误，应修复代码而非捕获。
 */
public class XmlException <: Exception {
    public init(message: String) {
        super(message)
    }

    public override func getClassName(): String {
        "XmlException"
    }
}
