package cangjie_xml.error

/**
 * CangjieXML 库统一的错误类型。
 *
 * 使用带上下文的枚举表达错误——比 tinyxml2 的整数错误码信息密度更高，
 * 也天然契合仓颉的模式匹配。
 *
 * ## 里程碑范围
 *
 * - M1（DOM 内核）：仅需要非常少量的错误分支，核心是 DOM 手工构造期间的
 *   参数校验（例如尝试给无父节点的节点调用 `removeSelf`）。
 * - M3（Parser）：将补齐 `MismatchedElement` / `InvalidAttribute` 等全部
 *   结构性解析错误。
 * - M6（IO + 收口）：将补齐 `FileNotFound` / `FileReadFailed` / `FileWriteFailed` 等 IO 错误。
 *
 * 因此在 M1 阶段，我们只落位 DESIGN 中承诺的完整枚举骨架——构造器全部保留，
 * 但暂时仅 DOM 操作会真正触发 `DomOperationFailed`。
 */
public enum XmlError <: ToString {
    /** DOM 手工构造时的非法操作（例如从空父节点移除）。 */
    | DomOperationFailed(String)
    /** 文件不存在（M6 使用）。 */
    | FileNotFound(String)
    /** 文件读取失败：path, cause（M6 使用）。 */
    | FileReadFailed(String, String)
    /** 文件写入失败：path, cause（M6 使用）。 */
    | FileWriteFailed(String, String)
    /** 空文档（M3 使用）。 */
    | EmptyDocument
    /** 起止标签不匹配：openTag, closeTag, at（M3 使用）。 */
    | MismatchedElement(String, String, SourcePos)
    /** 非法属性：name, at, reason（M3 使用）。 */
    | InvalidAttribute(String, SourcePos, String)
    /** 非法文本：at, reason（M3 使用）。 */
    | InvalidText(SourcePos, String)
    /** 非法注释：at, reason（M3 使用）。 */
    | InvalidComment(SourcePos, String)
    /** 非法 XML 声明：at, reason（M3 使用）。 */
    | InvalidDeclaration(SourcePos, String)
    /** 非法未知节点：at, reason（M3 使用）。 */
    | InvalidUnknownNode(SourcePos, String)
    /** 非法编码：at, reason（M3 使用）。 */
    | InvalidEncoding(SourcePos, String)
    /** 元素嵌套深度超限：limit, at（M3 使用）。 */
    | ElementDepthExceeded(Int64, SourcePos)
    /** 值编解码失败：targetType, text, at（M4 使用）。 */
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
 * - `XmlError`（包装在 Result 里）：可预期"可能失败"，调用方应显式处理。
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
