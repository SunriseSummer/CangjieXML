package cangjie_xml.dom

/**
 * XML 属性：挂在 `XmlElement` 上的名称/值对。
 *
 * ## 与 tinyxml2 的差异
 *
 * - tinyxml2 的 `XMLAttribute` 是链式结构且持有指向下一个属性的指针；
 *   我们把这类链表维护封到 `XmlElement` 内部，公共类型只保留干净的数据含义。
 * - 不是 `XmlNode` 的子类型——XML 规范中属性并非节点树成员，强行让它实现
 *   `XmlNode` 会使 `parent` / `siblings` 的语义含糊。
 * - 属性值一律以原始 `String` 形态保存；类型化访问（`intAttribute` 等）作为
 *   Query 层（M4）的扩展函数提供。
 *
 * `name` 与 `value` 均为 `var`，便于现场修改而无需替换整个属性对象。
 */
public class XmlAttribute {
    public var name: String
    public var value: String

    public init(name: String, value: String) {
        this.name = name
        this.value = value
    }
}
