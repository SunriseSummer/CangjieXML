package fastxml.dom

/**
 * XML 未知节点：承载解析器无法分类但仍需保留的内容。
 *
 * Parser 在遇到结构合法但无法识别的 `<!...>` / `<?...?>` 片段（典型如
 * `<!DOCTYPE ...>`）时使用。
 */
public class XmlUnknown <: XmlNode {
    public var value: String

    init(doc: XmlDocument, value: String) {
        super(doc)
        this.value = value
    }

    public override func kind(): XmlNodeKind {
        XmlNodeKind.Unknown(this)
    }
}
