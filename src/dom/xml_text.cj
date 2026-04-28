package fastxml.dom

/**
 * 文本节点
 *
 * 既覆盖普通 `PCDATA` 文本，也覆盖 `CDATA` 段：通过 `isCdata` 区分
 *
 * - `isCdata = false`（默认）：输出时按普通文本转义（`<`, `&` 等）
 * - `isCdata = true`：输出时包裹为 `<![CDATA[...]]>`，不做转义
 *
 * 由 `XmlDocument.createText()` 创建
 */
public class XmlText <: XmlNode {
    public var value: String
    public var isCdata: Bool

    init(doc: XmlDocument, value: String, isCdata: Bool) {
        super(doc)
        this.value = value
        this.isCdata = isCdata
    }

    public override func kind(): XmlNodeKind {
        XmlNodeKind.Text(this)
    }
}
