# 02 — 快速上手

## 环境要求

- **仓颉 SDK**：`1.0.5`
- 可选：用于 E2E 验收的 Python 3（`e2etest/xml/run.py`）

---

## 在项目中使用 CangjieXML

CangjieXML 以标准 `cjpm` 包形式组织。把它作为依赖引入后即可使用所有公共 API。

假设你的项目目录结构为：

```
my_app/
├── cjpm.toml
└── src/
    └── main.cj
```

在 `cjpm.toml` 中声明依赖（具体依赖声明语法以 `cjpm` 当前版本为准）后，即可
通过 `import fastxml.*` / `import fastxml.dom.*` 等方式引入。

---

## 第一个程序：构造并打印一棵 XML

```cangjie
import fastxml.dom.*
import fastxml.writer.*

main(): Int64 {
    let doc = XmlDocument()
    doc.appendChild(doc.createDeclaration())

    let root = doc.createElement("catalog")
    doc.appendChild(root)

    let book = doc.createElement("book")
    book.setAttribute("id", "1")
    book.setTextContent("SICP")
    root.appendChild(book)

    println(doc.writeToString())
    0
}
```

预期输出：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<catalog>
    <book id="1">SICP</book>
</catalog>
```

若需要紧凑输出：

```cangjie
println(doc.writeToString(XmlWriteOptions.compactPreset()))
```

```xml
<?xml version="1.0" encoding="UTF-8"?><catalog><book id="1">SICP</book></catalog>
```

---

## 第一个程序：解析 XML 字符串

```cangjie
import fastxml.dom.*
import fastxml.parser.*

main(): Int64 {
    let doc = parseXml("<catalog><book id=\"1\">SICP</book></catalog>")
    let root = doc.rootElement.getOrThrow()
    let book = root.firstChildElement(name: Some("book")).getOrThrow()
    println(book.textContent())    // "SICP"
    0
}
```

本示例使用了 `fastxml.parser` 包中的顶层函数 `parseXml(...)`。

---

## 下一步

- 系统了解节点模型 → [03 — DOM](./03-dom.md)
- 了解更强大的 **Builder DSL** → [07 — Builder](./07-builder.md)
- 想读写文件 → [09 — IO](./09-io.md)
- 了解解析器选项、错误处理 → [04 — Parser](./04-parser.md) 与
  [10 — 错误模型](./10-errors.md)
