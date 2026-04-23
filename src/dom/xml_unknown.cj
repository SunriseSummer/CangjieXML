package cangjie_xml.dom

/**
 * XML 未知节点：承载解析器无法分类但仍需保留的内容（典型是 `<!DOCTYPE ...>`）。
 *
 * 与 tinyxml2 的 `XMLUnknown` 等价。M1 阶段仅允许手工构造，由 Parser（M3）
 * 在遇到无法识别但结构合法的 `<!...>` / `<?...?>` 片段时使用。
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
