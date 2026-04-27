# 07 — Builder

包：`tinyxml2.build`

提供 DSL 风格的构造入口，在保持 `XmlDocument` 语义完整的前提下，显著降低
"手工 createElement + appendChild" 的噪音。

---

## `XmlDocumentBuilder`

### 典型用法

```cangjie
import tinyxml2.dom.*
import tinyxml2.build.*

let doc = XmlDocumentBuilder()
    .declaration()
    .comment("catalog of books")
    .root("catalog") { r =>
        r.element("book") { b =>
            b.attribute("id", "1").text("SICP")
        }
        r.element("book") { b =>
            b.attribute("id", "2").text("TAOCP")
        }
    }
    .build()
```

### API

```cangjie
public class XmlDocumentBuilder {
    public init()

    public func declaration(value!: ?String = None): XmlDocumentBuilder
    public func comment(value: String): XmlDocumentBuilder
    public func root(
        name: String,
        configure!: (XmlElementBuilder) -> Unit = {_ => ()}
    ): XmlDocumentBuilder

    public func build(): XmlDocument   // 返回底层文档（不是副本）
}
```

| 方法            | 行为                                                                                |
| --------------- | ----------------------------------------------------------------------------------- |
| `declaration`    | 追加 XML 声明；**幂等**——若已存在声明则不重复追加                                   |
| `comment`        | 追加顶层注释节点                                                                    |
| `root`           | 设置根元素（仅可调用一次，内部 `appendChild` 会受根唯一性约束）；在 lambda 内继续构造 |
| `build`          | 返回底层 `XmlDocument`；`build()` 可多次调用，返回同一实例                           |

**立即落地语义**：Builder 的每个方法都立即向底层 DOM 写入——不存在"先暂存再
一次性落地"。因此在 lambda 内部发生异常，DOM 上已经写入的节点不会回滚；这是
DESIGN 明确的权衡。

---

## `XmlElementBuilder`

在 `.root("name") { e => ... }` 或 `.element("child") { e => ... }` 的 lambda
参数里获得，**不能** 由用户直接 `new`。

### API

```cangjie
public class XmlElementBuilder {
    public func attribute(name: String, value: String): XmlElementBuilder
    public func attributeAs<T>(name: String, value: T, codec: XmlValueCodec<T>): XmlElementBuilder
    public func text(value: String, cdata!: Bool = false): XmlElementBuilder
    public func comment(value: String): XmlElementBuilder
    public func element(
        name: String,
        configure!: (XmlElementBuilder) -> Unit = {_ => ()}
    ): XmlElementBuilder

    public func build(): XmlElement    // 返回底层元素
}
```

### 小例：类型化属性

```cangjie
import tinyxml2.dom.*
import tinyxml2.build.*
import tinyxml2.query.*

let doc = XmlDocumentBuilder()
    .declaration()
    .root("catalog") { r =>
        r.element("book") { b =>
            b.attributeAs<Int64>("id", 1, INT64_CODEC)
             .attributeAs<Bool>("avail", true, BOOL_CODEC)
             .text("SICP")
        }
    }
    .build()

let book = doc.rootElement.getOrThrow().requiredChildElement("book")
book.intAttribute("id")     // Some(1)
book.boolAttribute("avail") // Some(true)
book.textContent()          // "SICP"
```

### 小例：混合文本与子元素

```cangjie
let doc = XmlDocumentBuilder()
    .root("p") { p =>
        p.text("Hello ")
         .element("b") { b => b.text("world") }
         .text("!")
    }
    .build()

doc.writeToString(XmlWriteOptions(writeDeclaration: false))
// <p>Hello <b>world</b>!</p>
```

### 小例：CDATA

```cangjie
let doc = XmlDocumentBuilder()
    .root("code") { c =>
        c.text("x = 1; y = 2;", cdata: true)
    }
    .build()

doc.writeToString(XmlWriteOptions(writeDeclaration: false))
// <code><![CDATA[x = 1; y = 2;]]></code>
```

---

## 何时用 Builder，何时用裸 DOM

| 场景                                   | 推荐                                |
| -------------------------------------- | ----------------------------------- |
| 静态 / 半静态结构的文档构造            | **Builder**（更易读）              |
| 需要按数据动态拼接                     | Builder 也行，lambda 内自由循环     |
| 在既有 DOM 上做局部修改                | 裸 DOM（Builder 不是"编辑器"）     |
| 要回滚 / 事务性构造                    | 需自行策略；Builder 是立即落地语义  |
