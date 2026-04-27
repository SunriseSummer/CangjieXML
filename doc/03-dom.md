# 03 — DOM

包：`tinyxml2.dom`

DOM 内核是 CangjieXML 的基石。所有其他子包——Parser、Writer、Query、Builder、
Visit、IO——都围绕这份节点模型构建。

---

## 节点层级

```text
XmlNode (sealed abstract class)
├─ XmlDocument      // 文档根
├─ XmlElement       // 元素
├─ XmlText          // 文本 / CDATA
├─ XmlComment       // 注释
├─ XmlDeclaration   // <?xml ... ?>
└─ XmlUnknown       // <!DOCTYPE ...> 等
```

> `XmlAttribute` **不是** `XmlNode` 的子类型 —— 这与 XML 规范中"属性不是节点
> 树成员"的语义一致。它是一个独立的轻量数据类。

### `XmlNodeKind`：模式匹配入口

```cangjie
public enum XmlNodeKind {
    | Document(XmlDocument)
    | Element(XmlElement)
    | Text(XmlText)
    | Comment(XmlComment)
    | Declaration(XmlDeclaration)
    | Unknown(XmlUnknown)
}
```

示例：

```cangjie
match (node.kind()) {
    case Element(e) => println("<${e.name}>")
    case Text(t)    => println(t.value)
    case _          => ()
}
```

每个构造器直接携带具体类型实例——模式匹配分支里的变量就是打开过的具体类型，
无需再做转型。

---

## `XmlNode`：所有节点的共通 API

| 成员                                           | 说明                                                       |
| ---------------------------------------------- | ---------------------------------------------------------- |
| `document: XmlDocument`                         | 节点所属文档；对 `XmlDocument` 自身返回 `this`             |
| `parent: ?XmlElement`                           | 父元素；根元素 / 文档直挂节点为 `None`                     |
| `previousSibling: ?XmlNode` / `nextSibling: ?XmlNode` | 兄弟节点                                              |
| `kind(): XmlNodeKind`                           | 返回 `enum`，用于模式匹配                                  |
| `removeSelf(): Bool`                            | 从父 / 文档解挂；若当前无父返回 `false`                    |
| `operator ==` / `operator !=`                   | **身份比较**（`refEq`）；深等比较见未来版本                |

`document` 对 `XmlDocument` 自身返回 `this`；其他节点总是非空（由创建工厂保证）。

---

## `XmlDocument`

### 构造

```cangjie
public init()
```

创建一个空文档，既无声明也无根元素。`hasBom = false`、`writeBom = false`。

### 便捷访问

| 属性 / 方法                              | 含义                                   |
| ---------------------------------------- | -------------------------------------- |
| `declaration: ?XmlDeclaration`            | 文档的 `<?xml ... ?>`（若存在）       |
| `rootElement: ?XmlElement`                | 文档的根元素（若存在）                 |
| `firstChild: ?XmlNode` / `lastChild`      | 首 / 末顶层节点（任意类型）           |
| `childNodes(): Iterable<XmlNode>`         | 顺序遍历所有顶层节点                   |

### 节点工厂

所有节点构造器均为包级不可见——用户只能通过这组 `createXxx` 工厂创建节点，
借此强制"每个节点都归属一个文档"的不变量。

```cangjie
public func createElement(name: String): XmlElement
public func createText(value: String, cdata!: Bool = false): XmlText
public func createComment(value: String): XmlComment
public func createDeclaration(value!: ?String = None): XmlDeclaration
public func createUnknown(value: String): XmlUnknown
```

- `createDeclaration` 传 `None` 时使用默认声明 `xml version="1.0" encoding="UTF-8"`。
- 工厂方法**不会**把节点挂到树上，需要自行 `appendChild` / `prependChild` / `insertChildBefore`。

### 顶层节点管理

```cangjie
public func appendChild(node: XmlNode): Unit
public func prependChild(node: XmlNode): Unit
public func removeChild(node: XmlNode): Bool
public func clear(): Unit
```

**约束（违者抛 `XmlException`）**：

1. 顶层不允许 `XmlDocument` / `XmlText`；
2. 至多一个 `XmlElement`（根元素）；
3. 至多一条 `XmlDeclaration`，且必须是首个顶层节点；
4. 节点必须归属本文档（禁止跨文档插入）。

`removeChild` 对不属于本文档顶层的节点返回 `false`（不抛异常）。

`clear` 清空所有顶层节点并重置链表，但**不**重置 `hasBom` / `writeBom`。

### 文档级元信息

```cangjie
public var hasBom: Bool        // 解析时填充
public var writeBom: Bool      // 写出时决定是否输出 BOM
```

### 示例：手工构造 + 遍历

```cangjie
let doc = XmlDocument()
doc.appendChild(doc.createDeclaration())

let root = doc.createElement("catalog")
doc.appendChild(root)
doc.appendChild(doc.createComment("end"))

// 顶层遍历：声明 + 元素 + 注释
var kinds = ""
for (n in doc.childNodes()) {
    match (n.kind()) {
        case Declaration(_) => kinds += "D"
        case Element(_)     => kinds += "E"
        case Comment(_)     => kinds += "C"
        case _              => kinds += "?"
    }
}
// kinds == "DEC"
```

---

## `XmlElement`

### 基本

```cangjie
public var name: String
```

`name` 是唯一可直接修改的字段；属性通过专门 API 管理。

### 属性 API

```cangjie
public func attribute(name: String): ?String
public func hasAttribute(name: String, value!: ?String = None): Bool
public func setAttribute(name: String, value: String): Unit
public func tryAddAttribute(name: String, value: String): Bool
public func removeAttribute(name: String): Bool
public func attributes(): Iterable<XmlAttribute>
public func attributeCount(): Int64
public func attributeAt(i: Int64): XmlAttribute
```

- **顺序保留**：`attributes()` 按插入顺序返回，与序列化输出顺序一致。
- **同名覆盖**：`setAttribute` 对已存在属性覆盖值，**不**改变其顺序。
- **同名不覆盖**：`tryAddAttribute` 仅在不存在同名属性时新增；返回 `false`
  即"重复属性"，调用方决定如何处理。相比 `hasAttribute(...) + setAttribute(...)`
  的两次查询路径，单次 `tryAddAttribute` 只做一次 lookup，是 parser 等
  "已知属性必须唯一"的高频路径首选入口。
- **属性查找**：典型 XML 元素属性数 ≤ 8，库内对名称查找走纯线性扫描；
  超过阈值后元素内部按需建立 `HashMap` 名称索引，使大批量属性场景仍保
  持均摊 O(1)。这一切对调用方完全透明。
- **索引访问**：`attributeAt(i)` 按插入顺序索引访问（0 ≤ `i` < `attributeCount()`）；
  越界抛 `IndexOutOfBoundsException`。提供索引访问的目的是给热路径（writer 序列化、
  批量诊断）一条不分配 `Iterator` 对象的遍历方式：
  `for i in 0..el.attributeCount() { let a = el.attributeAt(i); ... }`
  比 `for a in el.attributes()` 在 N 万元素 × M 属性的场景上少分配 N 个迭代器对象。
- `hasAttribute(name, value: Some(v))`：同时检查存在性 + 值相等。

### 子节点 API

```cangjie
public func appendChild(node: XmlNode): Unit
public func prependChild(node: XmlNode): Unit
public func insertChildBefore(reference: XmlNode, node: XmlNode): Unit
public func removeChild(node: XmlNode): Bool

public func childNodes(): Iterable<XmlNode>
public func childElements(name!: ?String = None): Iterable<XmlElement>
public func firstChildElement(name!: ?String = None): ?XmlElement

public prop firstChild: ?XmlNode
public prop lastChild: ?XmlNode
public func isEmpty(): Bool
```

**安全约束（违者抛 `XmlException`）**：

- 禁止将元素作为自己的祖先 / 后代（成环检测）；
- 禁止跨文档插入；
- 禁止将 `XmlDocument` / `XmlDeclaration` 作为元素子节点；
- 插入已在别处的节点时自动先解挂（DOM 移动语义）。

`removeChild` 对不属于本元素直接子节点的节点返回 `false`。

### 文本内容 API

```cangjie
public func textContent(): String
public func setTextContent(value: String): Unit
```

- `textContent()`：递归拼接所有后代 `XmlText` 的 `value`，CDATA 与普通文本一视同仁。
- `setTextContent(value)`：清空所有子节点 + 追加单个非 CDATA `XmlText`。

如果需要 CDATA，请用 `doc.createText(value, cdata: true)` + `appendChild`。

### 示例：属性与查询

```cangjie
let doc = XmlDocument()
let e = doc.createElement("book")
e.setAttribute("id", "1")
e.setAttribute("lang", "en")
doc.appendChild(e)

println(e.attribute("id"))              // Some("1")
println(e.attributeCount())             // 2
println(e.hasAttribute("lang"))         // true
println(e.hasAttribute("id", value: Some("1"))) // true
println(e.hasAttribute("id", value: Some("9"))) // false

// 索引访问（性能敏感场景，避免迭代器分配）
var i = 0
while (i < e.attributeCount()) {
    let a = e.attributeAt(i)
    println("${a.name}=${a.value}")     // id=1, lang=en
    i++
}

// 不覆盖式新增（适合 parser、批量导入等"重复名应报错"路径）
println(e.tryAddAttribute("genre", "fiction")) // true
println(e.tryAddAttribute("id", "9"))          // false（已存在）
```

---

## `XmlAttribute`

```cangjie
public class XmlAttribute {
    public let name: String
    public var value: String
}
```

- `name` 不可就地修改——改名需走 `removeAttribute(old)` + `setAttribute(new, value)`。
- `value` 可直接 `attr.value = "..."` 修改（更常用 `setAttribute` 入口）。

---

## `XmlText`

```cangjie
public class XmlText <: XmlNode {
    public var value: String
    public var isCdata: Bool
}
```

- `isCdata = false`：输出时按文本转义（`&` / `<` / `>` → 实体）。
- `isCdata = true`：输出时包裹为 `<![CDATA[ ... ]]>`；若内容含 `]]>`，序列化器
  自动按规范分段。

---

## `XmlComment` / `XmlDeclaration` / `XmlUnknown`

```cangjie
public class XmlComment <: XmlNode      { public var value: String }
public class XmlDeclaration <: XmlNode  { public var value: String }
public class XmlUnknown <: XmlNode      { public var value: String }
```

- `XmlComment.value`：注释正文，不含 `<!--` / `-->`。
- `XmlDeclaration.value`：`<?xml` 与 `?>` 之间的完整原始字符串（如 `xml version="1.0" encoding="UTF-8"`）。
- `XmlUnknown`：承载 `<!DOCTYPE ...>`、处理指令等解析器无法归类但结构合法的片段。

### 默认声明常量

```cangjie
public const DEFAULT_DECLARATION_VALUE: String = "xml version=\"1.0\" encoding=\"UTF-8\""
```

在 `writer` 包中还有一份同值的 `DEFAULT_XML_DECLARATION_VALUE`，两者有意独立以避免
反向依赖。

---

## 错误类型

DOM 手工构造时的非法操作会抛 `XmlException`（来自 `tinyxml2.error`）。
`XmlException` 是"**程序员错误**"——用户应修正代码，通常不需要 `catch`。

详见 [10 — 错误模型](./10-errors.md)。
