# CangjieXML

> 纯仓颉实现的 XML 库——受 [tinyxml2](https://github.com/leethomason/tinyxml2) 启发，但
> **不是** 对 tinyxml2 的逐行翻译。在保留其务实的能力边界（DOM + 基础读写）的同时，
> 以仓颉的 `enum` / 模式匹配 / `Option` / 扩展 / 泛型 重建 API，使其"看起来像仓颉库"，
> 而不是"C++ 库的投影"。
>
> 设计详情见 [`DESIGN.md`](./DESIGN.md)，迭代节奏见 [`ROADMAP.md`](./ROADMAP.md)，
> 当前进度见 [`progress.md`](./progress.md)。

---

## 当前状态

| 里程碑 | 状态 |
|---|---|
| M0 项目脚手架 | ✅ |
| M1 DOM 内核  | ✅ |
| M2 Writer    | ⏳ |
| M3 Parser    | ⏳ |

目前已经可以 **手工构造** 完整的 XML DOM 树，并对其进行增删改查；
**解析** 与 **序列化** 将在后续迭代上线。

---

## 快速上手

### 构建与测试

```bash
source /opt/cangjie/envsetup.sh   # 或自行配置 cangjie SDK 1.0.5
cjpm build
cjpm test
```

### 示例：手工构造一棵 DOM

```cangjie
import cangjie_xml.dom.*

main() {
    let doc = XmlDocument()
    doc.appendChild(doc.createDeclaration())          // <?xml version="1.0" encoding="UTF-8"?>

    let root = doc.createElement("catalog")
    doc.appendChild(root)

    let book = doc.createElement("book")
    book.setAttribute("id", "1")
    book.setTextContent("SICP")
    root.appendChild(book)

    // 遍历子元素
    for (b in root.childElements(name: Some("book"))) {
        println("${b.attribute(\"id\") ?? \"?\"}: ${b.textContent()}")
    }
    // 输出: 1: SICP

    0
}
```

---

## 已实现模块

### `cangjie_xml`（根包）

- `CANGJIE_XML_VERSION: String`：版本号常量。
- `cangjieXmlVersion(): String`：运行时探测版本。

### `cangjie_xml.error`

| 类型 | 说明 |
|---|---|
| `SourcePos` | 源文本位置（`offset` / `line` / `column`）。`SourcePos.zero()` 提供默认值。 |
| `XmlError` | 库级错误枚举。共 14 个构造器，M1 仅启用 `DomOperationFailed`；其他构造器在 M3 / M4 / M6 激活。实现 `ToString`。 |
| `XmlException` | 不可预期的 API 误用异常（例如成环、跨文档插入）。 |

### `cangjie_xml.dom` —— DOM 内核

#### 类型总览

```text
XmlNode (sealed abstract)
├─ XmlDocument      // 文档根
├─ XmlElement       // 元素
├─ XmlText          // 文本 / CDATA
├─ XmlComment       // 注释
├─ XmlDeclaration   // <?xml ... ?>
└─ XmlUnknown       // <!DOCTYPE ...> 等
```

`XmlAttribute` 独立为一个简单数据类，**不是** `XmlNode` 的子类型——这符合 XML 规范中
"属性不是节点树成员"的语义。

#### 共通导航（`XmlNode`）

| 成员 | 说明 |
|---|---|
| `document: XmlDocument` | 节点所属文档；对 `XmlDocument` 自身返回 `this` |
| `parent: ?XmlElement` | 父元素；根元素 / 文档直挂节点为 `None` |
| `previousSibling: ?XmlNode` / `nextSibling: ?XmlNode` | 兄弟节点 |
| `kind(): XmlNodeKind` | 返回 `enum`，用于模式匹配 |
| `removeSelf(): Bool` | 从父节点脱离；若当前无父，返回 `false` |

> 模式匹配示例：
> ```cangjie
> match (node.kind()) {
>     case Element(e) => println(e.name)
>     case Text(t)    => println(t.value)
>     case _          => ()
> }
> ```

#### `XmlDocument`

- **节点工厂**：`createElement` / `createText(value, cdata:)` / `createComment` /
  `createDeclaration(value:)` / `createUnknown`。所有工厂方法自动将新节点绑定到
  当前文档。
- **顶层节点管理**：`appendChild` / `prependChild` / `removeChild` / `clear`。
  约束：
  - 最多一个根元素、最多一条 `XmlDeclaration`（且必须位于最前）；
  - 顶层不允许裸 `XmlText`；
  - 禁止跨文档插入。
- **便捷访问**：`rootElement: ?XmlElement`、`declaration: ?XmlDeclaration`、
  `firstChild` / `lastChild` / `childNodes()`。
- **文档级元信息**：`hasBom: Bool`（解析时填充，M3 起）、`writeBom: Bool`
  （写出时决定是否输出 BOM，M2 起使用）。

#### `XmlElement`

- **属性 API**
  - `attribute(name): ?String`
  - `hasAttribute(name, value: ?String)`
  - `setAttribute(name, value)`——同名后写覆盖，保留首次插入顺序
  - `removeAttribute(name): Bool`
  - `attributes(): Iterable<XmlAttribute>`（按插入顺序）
  - `attributeCount(): Int64`
- **子节点 API**
  - `appendChild` / `prependChild` / `insertChildBefore(reference, node)` / `removeChild`
  - `childNodes()` / `childElements(name:)` / `firstChildElement(name:)`
  - `firstChild: ?XmlNode` / `lastChild: ?XmlNode` / `isEmpty(): Bool`
  - **安全约束**：
    - 禁止将节点作为自己的祖先 / 后代（成环检测）；
    - 禁止跨文档插入；
    - 节点从其他父节点 / 文档插入时自动先解挂（DOM 移动语义）；
    - 禁止将 `XmlDocument` 或 `XmlDeclaration` 作为元素子节点。
- **文本 API**
  - `textContent(): String`——递归拼接所有后代 `XmlText` 的 `value`；
  - `setTextContent(value)`——清空子节点后追加单个非 CDATA `XmlText`。

#### `XmlAttribute` / `XmlText` / `XmlComment` / `XmlDeclaration` / `XmlUnknown`

轻量数据类，字段均可变。`XmlText` 额外带 `isCdata: Bool` 标志 CDATA 段。

---

## 与 tinyxml2 的映射

见 [`DESIGN.md` §15](./DESIGN.md)。关键差异：

| tinyxml2 | CangjieXML | 原因 |
|---|---|---|
| `XMLHandle` / `XMLConstHandle` | `Option<T>` + `?.` / `??` | 语言特性天然覆盖 |
| `ToElement()` / `ToText()` | `match (node.kind())` | 模式匹配优雅于运行时转型 |
| `MemPool` / `StrPair` | （不提供） | GC 语言的职责边界 |
| 全局静态写出开关 | `XmlWriteOptions` | 显式配置，多线程安全 |

---

## 路线图快照

```text
M0 脚手架  ✅
  ↓
M1 DOM 内核  ✅  ← 你当前所处的稳定面
  ↓
M2 Writer
  ↓
M3 Parser
  ↓
M4 Query + Builder
  ↓
M5 Visit
  ↓
M6 IO + Error + Options 收口
  ↓
M7 Batch / Concurrency 边界
  ↓
M8 回归 / 基准 / 文档 / v1.0 发布
```

## 许可证

TBD。
