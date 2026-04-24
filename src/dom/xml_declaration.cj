package cangjie_xml.dom

/**
 * XML 声明节点：`<?xml version="1.0" encoding="UTF-8"?>`。
 *
 * `value` 为 `<?xml` 与 `?>` 之间的原始字符串。M1 阶段保持整块保存，
 * Parser 阶段（M3）再视需要拆解成 version/encoding/standalone 属性。
 *
 * 一个文档至多允许一条声明，且必须出现在所有其他节点之前——该约束由
 * `XmlDocument` 在插入时校验，这里保持类型本体纯净。
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
