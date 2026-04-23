package cangjie_xml.build

import cangjie_xml.dom.*
import cangjie_xml.query.*

/**
 * 元素构建器。**不是** 并行的 DOM——`build()` 的产物仍是普通 `XmlElement`。
 *
 * ## 设计要点
 *
 * - 每次配置调用都返回 `this`，允许链式；
 * - 子作用域通过 lambda 传入，形成近似 DSL 的结构化书写；
 * - 内部持有一个实际的 `XmlElement`，所有操作立即落回 DOM——因此即便
 *   用户在 lambda 内拿到同一个 builder 并越权越界，也不会破坏 DOM 不变量
 *   （最多是逻辑不合预期）。
 *
 * ## 为什么不做懒构造
 *
 * 延迟到 `build()` 再一次性落地能提供更强的事务性校验（例如出错全回滚），
 * 但也要求 Builder 复刻一套平行表示——正是 DESIGN §10.3 明确反对的。
 * 立即落回 DOM 的做法保持了"Builder 只是体验层"的定位。
 */
public class XmlElementBuilder {
    let target: XmlElement

    init(target: XmlElement) {
        this.target = target
    }

    /** 设置属性（字符串）。 */
    public func attribute(name: String, value: String): XmlElementBuilder {
        target.setAttribute(name, value)
        this
    }

    /** 用 codec 格式化后设置属性。便于写 `.attributeAs("age", 18, INT64_CODEC)`。 */
    public func attributeAs<T>(name: String, value: T, codec: XmlValueCodec<T>): XmlElementBuilder {
        target.setAttribute(name, codec.format(value))
        this
    }

    /** 追加文本子节点（可选 CDATA）。 */
    public func text(value: String, cdata!: Bool = false): XmlElementBuilder {
        target.appendChild(target.document.createText(value, cdata: cdata))
        this
    }

    /** 追加注释子节点。 */
    public func comment(value: String): XmlElementBuilder {
        target.appendChild(target.document.createComment(value))
        this
    }

    /**
     * 追加子元素；可在 `configure` 内继续配置子元素。
     *
     * ```cangjie
     * builder.element("book") { child =>
     *     child.attribute("id", "1").text("SICP")
     * }
     * ```
     */
    public func element(
        name: String,
        configure!: (XmlElementBuilder) -> Unit = {_ => ()}
    ): XmlElementBuilder {
        let child = target.document.createElement(name)
        target.appendChild(child)
        configure(XmlElementBuilder(child))
        this
    }

    /** 结束本层，返回正在构造的 `XmlElement`。 */
    public func build(): XmlElement {
        target
    }
}
