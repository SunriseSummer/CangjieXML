package fastxml.dom

/**
 * XML 注释节点：`<!-- value -->`
 *
 * `value` 为注释内容原文，不包含两侧的 `<!--` / `-->` 分隔符
 */
public class XmlComment <: XmlNode {
    public var value: String

    init(doc: XmlDocument, value: String) {
        super(doc)
        this.value = value
    }

    public override func kind(): XmlNodeKind {
        XmlNodeKind.Comment(this)
    }
}
