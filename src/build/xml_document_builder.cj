package cangjie_xml.build

import cangjie_xml.dom.*

/**
 * 文档构建器——提供自顶向下的 DSL 式构造入口。
 *
 * ```cangjie
 * let doc = XmlDocumentBuilder()
 *     .declaration()
 *     .root("catalog") { r =>
 *         r.element("book") { b =>
 *             b.attribute("id", "1").text("SICP")
 *         }
 *     }
 *     .build()
 * ```
 *
 * 与 `XmlElementBuilder` 一样，内部直接向 `XmlDocument` 落地；`build()` 返回的
 * 是同一个文档实例，**不是**一份副本。
 */
public class XmlDocumentBuilder {
    let doc: XmlDocument

    public init() {
        this.doc = XmlDocument()
    }

    /**
     * 追加 XML 声明。若已存在声明则复用，不重复追加（避免多次调用出错）。
     *
     * `value` 语义对齐 `XmlDocument.createDeclaration(value:)`：为 `None` 时
     * 采用 DOM 包内的默认声明文本。
     */
    public func declaration(value!: ?String = None): XmlDocumentBuilder {
        if (doc.declaration.isNone()) {
            doc.appendChild(doc.createDeclaration(value: value))
        }
        this
    }

    /** 追加顶层注释节点。 */
    public func comment(value: String): XmlDocumentBuilder {
        doc.appendChild(doc.createComment(value))
        this
    }

    /**
     * 设置（或创建）根元素，并允许在 `configure` 内继续构建。
     *
     * 约束：一个文档只能有一个根元素。重复调用会抛 `XmlException`
     * （由 `XmlDocument.appendChild` 的根唯一性检查保障）。
     */
    public func root(
        name: String,
        configure!: (XmlElementBuilder) -> Unit = {_ => ()}
    ): XmlDocumentBuilder {
        let el = doc.createElement(name)
        doc.appendChild(el)
        configure(XmlElementBuilder(el))
        this
    }

    /** 返回已构造好的文档。 */
    public func build(): XmlDocument {
        doc
    }
}
