# 08 — Visit

包：`fastxml.visit`

提供两种遍历范式，按风格任选：

- **函数式 `walk`**：把一个 lambda 按前序派发到每个节点，返回 `XmlWalkControl`
  精确控制流程。
- **经典 `XmlVisitor`**：对称 `visitEnter` / `visitExit` 的 OO 访问者，对齐
  tinyxml2。

两种形态可互相替换，选择哪种取决于团队习惯与业务结构。

---

## 函数式 `walk`

### 顶层函数

```cangjie
public func walk(node: XmlNode, visit: (XmlNodeKind) -> XmlWalkControl): Unit
```

### 控制信号

```cangjie
public enum XmlWalkControl {
    | Continue        // 继续进入子节点，然后处理兄弟
    | SkipChildren    // 不进入子节点，直接处理兄弟
    | Stop            // 立即终止整次 walk
}
```

在 `XmlVisitor` 中 `false` 既可能代表"跳过子节点"也可能代表"立即中止"，语义歧义；
`walk` 显式用三态枚举区分。

### 语义

- 每个节点前序调用 `visit(node.kind())` 一次；
- `Continue`：进入子节点（仅 `Document` / `Element` 才有子节点）；
- `SkipChildren`：对叶子节点（`Text` / `Comment` / `Declaration` / `Unknown`），
  `SkipChildren` 与 `Continue` 行为相同；
- `Stop`：立即结束整棵遍历。

### 实例方法形式

```cangjie
// XmlVisitable 接口植入到 XmlNode
doc.walk { kind =>
    match (kind) {
        case Element(e) => println(e.name); Continue
        case _          => Continue
    }
}
```

### 小例：统计指定名称的元素数量

```cangjie
class Acc { public var n: Int64 = 0 }
let count = Acc()
walk(doc) { kind =>
    match (kind) {
        case Element(e) where e.name == "book" =>
            count.n++
            SkipChildren           // 不再进入 book 的子树
        case _ => Continue
    }
}
println(count.n)
```

注意：`walk` 的回调是 lambda；cjc 1.0.5 禁止 lambda 捕获可变 `var`，
聚合计数时需要把状态封装进 `class`（如 `Acc`）。

---

## 经典 `XmlVisitor`

### 接口

```cangjie
public interface XmlVisitor {
    func visitEnter(document: XmlDocument): Bool { true }
    func visitExit(document: XmlDocument): Bool  { true }
    func visitEnter(element: XmlElement): Bool   { true }
    func visitExit(element: XmlElement): Bool    { true }

    func visit(text: XmlText): Bool              { true }
    func visit(comment: XmlComment): Bool        { true }
    func visit(declaration: XmlDeclaration): Bool{ true }
    func visit(unknown: XmlUnknown): Bool        { true }
}
```

所有方法都带默认实现 `{ true }`，子类**只需实现关心的几个**即可。

### 顶层函数

```cangjie
public func accept(node: XmlNode, visitor: XmlVisitor): Bool
```

也通过 `XmlVisitable` 扩展挂在 `XmlNode` 上：

```cangjie
doc.accept(MyVisitor())
```

### 返回值语义（对齐 tinyxml2）

- **`visitEnter(...)` 返回 `false`**：跳过当前节点子树，**不**调用对应的
  `visitExit`；外层对兄弟节点仍可继续。
- **叶子 `visit(...)` 返回 `false`**：立即终止整次 `accept`，`accept` 返回 `false`。
- **子节点 `accept` 返回 `false`**：中止剩余兄弟的处理，但仍调用 `visitExit`。
- **`visitExit(...)` 返回 `false`**：表示"看完这棵子树就够了"，外层也停止。

### 与 tinyxml2 的差异

1. `visitEnter(XmlElement)` 不单独传入属性链——在访问者里直接
   `element.attributes()` 迭代即可；签名更干净。
2. 所有方法有默认实现，无需全部覆写。
3. 使用函数重载区分 `visit(XmlText)` / `visit(XmlComment)` / …，而非
   `VisitText` / `VisitComment` 的串行命名。

### 小例：打印所有元素名

```cangjie
class NamePrinter <: XmlVisitor {
    public func visitEnter(element: XmlElement): Bool {
        println("<${element.name}>")
        true
    }
}
doc.accept(NamePrinter())
```

### 小例：收集所有文本

```cangjie
class TextBag <: XmlVisitor {
    public let parts: ArrayList<String> = ArrayList<String>()
    public func visit(text: XmlText): Bool {
        parts.add(text.value)
        true
    }
}
let bag = TextBag()
doc.accept(bag)
// bag.parts 现在包含所有后代文本片段
```

---

## `walk` vs `XmlVisitor`：如何选择

| 需求                                    | 推荐               |
| --------------------------------------- | ------------------ |
| 一处小逻辑、只关心少数节点类型          | `walk` + 模式匹配  |
| 需要 enter / exit 对称的生命周期回调    | `XmlVisitor`       |
| 需要"跳过子树但不终止" vs "立即终止" 区分 | `walk`（三态枚举） |
| 熟悉 tinyxml2 / Java XMLReader 风格      | `XmlVisitor`       |
| 在大量节点上做纯函数聚合                 | `walk`            |
