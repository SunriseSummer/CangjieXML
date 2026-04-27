package fastxml.dom

/**
 * XML 声明节点：`<?xml version="1.0" encoding="UTF-8"?>`。
 *
 * `value` 为 `<?xml` 与 `?>` 之间的原始字符串。
 *
 * 一个文档至多允许一条声明，且必须出现在所有其他节点之前——该约束由
 * `XmlDocument` 在插入时校验。
 */
public class XmlDeclaration <: XmlNode {
    public var value: String

    init(doc: XmlDocument, value: String) {
        super(doc)
        this.value = value
    }

    public override func kind(): XmlNodeKind {
        XmlNodeKind.Declaration(this)
    }
}
