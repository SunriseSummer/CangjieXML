package cangjie_xml.dom

/**
 * XML 未知节点：承载解析器无法分类但仍需保留的内容（典型是 `<!DOCTYPE ...>`）。
 *
 * 与 tinyxml2 的 `XMLUnknown` 等价；Parser 在遇到结构合法但无法识别的
 * `<!...>` / `<?...?>` 片段时使用。
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
