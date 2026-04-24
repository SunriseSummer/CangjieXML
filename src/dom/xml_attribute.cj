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
 * `value` 为 `var`，允许就地改值；`name` 为 `let`（见字段注释）。
 */
public class XmlAttribute {
    /**
     * 属性名不可就地修改——原因见下方注释块。改名请走"`removeAttribute(oldName)`
     * + `setAttribute(newName, value)`"，以保持 `XmlElement` 内部的 `attrIndex`
     * 与 `attrOrder` 两份结构同步。
     *
     * 曾经把 `name` 做成 `var`，会引入一个隐蔽 bug：用户在拿到 `XmlAttribute` 引用
     * 后直接 `attr.name = "x"`，`attrIndex` 的 key 仍是旧名，下一次 `attribute("x")`
     * 读不到值。没有强制不可变就没有办法在 DOM 层代价可接受地挡住这条路。
     */
    public let name: String
    public var value: String

    public init(name: String, value: String) {
        this.name = name
        this.value = value
    }
}
