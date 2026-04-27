# CangjieXML 开发进度

> 记录 CangjieXML 相对 tinyxml2 **全量功能** 的实现进度，并跟踪每次迭代的增量。

---

## 1. 里程碑看板

| 里程碑 | 名称 | 状态 | 说明 |
|---|---|---|---|
| M0 | 项目脚手架 | ✅ 已完成 | 迭代 1 |
| M1 | DOM 内核 | ✅ 已完成 | 迭代 1 |
| M2 | Writer | ✅ 已完成 | 迭代 2 |
| 质量红线 | 单文件≤300行 / 无下划线前缀 / 低圈复杂度 / 无魔鬼数 | ✅ 已落地 | 迭代 3（阶段 A） |
| M3 | Parser | ✅ 已完成 | 迭代 3（阶段 B） |
| M4 | Query + Builder | ✅ 已完成 | 迭代 4 |
| M5 | Visit | ✅ 已完成 | 迭代 5 |
| M6 | IO + Error 收口 | ✅ 已完成 | 迭代 6 |
| M6 | IO + Error + Options 收口 | ✅ 已完成 | 迭代 6 |
| M7 | Batch / Concurrency | ⛔ 跳过 | 与 DOM 单线程契约冲突，后续大版本再议 |
| M8 | 回归 / E2E / 发布 | ✅ 已完成 | **迭代 7（本次）** |

---

## 2. 按 tinyxml2 能力域的对照

tinyxml2 v11.0.0 公共 API 能力清单（按 DESIGN.md §3.2 归纳），以及当前 CangjieXML 实现状态：

| # | tinyxml2 能力 | CangjieXML 对应 | 状态 |
|---|---|---|---|
| 1 | DOM：`XMLDocument` / `XMLElement` / `XMLText` / `XMLComment` / `XMLDeclaration` / `XMLUnknown` / `XMLAttribute` | `dom.XmlDocument` / `XmlElement` / `XmlText` / `XmlComment` / `XmlDeclaration` / `XmlUnknown` / `XmlAttribute` | ✅ 已覆盖（M1） |
| 2 | 解析：`Parse(const char*)` / `LoadFile` / 流式 / 字节数组 | `parser.parseXml` / `io.loadXmlFromFile` / `io.parseXmlBytes` | ✅ 已完成（M3 + M6） |
| 3 | 序列化：`XMLPrinter` / `Print` / 紧凑 vs 格式化 | `writer.XmlWriter` + `XmlDocument/XmlElement.writeToString` | ✅ 已覆盖（M2） |
| 4 | 类型化属性：`IntAttribute` / `BoolAttribute` / `QueryXxx` | `query.*` 扩展 + `XmlValueCodec<T>` | ✅ 已完成（M4） |
| 5 | 访问者：`XMLVisitor` + `Accept` | `visit.XmlVisitor` + `walk()` | ✅ 已完成（M5） |
| 6 | 安全导航：`XMLHandle` / `XMLConstHandle` | 以 `Option<T>` + `?.` / `??` 语言原生替代 | ✅ 已用语言特性替代（M1） |
| 7 | 错误报告：错误码 + 行号 + 附加文本 | `error.XmlError` 枚举 + `SourcePos` + `XmlParseException` | ✅ 已完成（M3） |
| 8 | 空白策略：`PRESERVE_WHITESPACE` / `COLLAPSE_WHITESPACE` / `PEDANTIC_WHITESPACE` | `parser.XmlWhitespaceMode` | ✅ `Preserve`/`Collapse` 已完成（M3）；`Pedantic` 按需再补 |
| 9 | 工程性保护：最大嵌套深度 | `XmlParseOptions.maxElementDepth`（默认 500） | ✅ 已完成（M3） |
| 10 | 全局静态写出开关（tinyxml2 有） | **不采用**，统一为 `XmlWriteOptions` 显式配置 | ✅（M2，显式优于隐式） |

图例： ✅ 已完成  🟡 部分完成  ⏳ 未开始

---

## 3. 迭代 1（M0 + M1）——见 git 历史

DOM 内核及脚手架。详见上一轮进度记录（commit `8d6cecd`）。

---

## 4. 迭代 2（M2 Writer）——本次

### 4.1 存量检视结论

复核 M1 DOM，确认 Writer 仅通过 `XmlNode` 公共导航 API（`firstChild` /
`nextSibling` / `kind()` / `childNodes()` / `attributes()` 等）即可完成全部遍历，
**无需修改 DOM 内核**。M1 的接口设计经受住了 Writer 的实际使用。

### 4.2 增量

- **`internal` 包**（新建）
  - `escapeText(s)`：PCDATA 转义（`&` / `<` / `>`），不含特殊字符走零分配快路径
  - `escapeAttribute(s)`：属性值转义（`&` / `<` / `>` / `"`）
  - `escapeCdata(s)`：CDATA 段构造，正确处理含 `]]>` 子串的情况（按规范分段）
  - `UTF8_BOM` / `UTF8_BOM_STRING`：BOM 常量

- **`writer` 包**（新建）
  - `XmlWriteOptions`：不可变 `struct`，封装 `compact` / `indent` / `lineEnd` /
    `writeDeclaration` / `writeBom` / `boolTrueText` / `boolFalseText`；
    提供 `default_()` / `compactPreset()` 工厂
  - `XmlSink` interface + `StringXmlSink` 默认实现
  - `XmlWriter`：递归下降写出器，对每种节点单独分派；自动识别自闭合、
    内联单文本、混合内容、块级嵌套四种排版情形
  - `extend XmlDocument { writeToString(options?: ...) }` 与
    `extend XmlElement { writeToString(options?: ...) }`：通过扩展声明把
    DESIGN §6.2 承诺的公共 API 植回 DOM 类型，同时保留 `dom` 包不依赖 `writer`

### 4.3 排版决策

| 元素内容 | 输出形态 | 示例 |
|---|---|---|
| 无子节点 | 自闭合 | `<e/>` |
| 单个文本子节点 | 内联 | `<e>text</e>` |
| **任一**子节点为文本 / CDATA（混合内容） | 全内联 | `<e>a<b/>c</e>` |
| 全部子节点为元素 / 注释 / 未知节点 | 块级缩进 | `<r>\n    <a/>\n    <b/>\n</r>` |

关键取舍：混合内容**不换行**——因为在 XML 中文本节点空白具有语义，
机械插入 `\n` 或缩进会改变文档意义。这与 tinyxml2 的策略一致，也是
"先正确、再美化" 的原则。

### 4.4 质量门禁

| 门禁 | 状态 |
|---|---|
| `cjpm build` | ✅ 成功（仅两条 `writeToString` unused-warning，因公共 API 在库内未被调用，属预期） |
| `cjpm test` | ✅ **42/42 通过**（20 DOM + 21 Writer + 1 根包） |
| 确定性契约 | ✅ 专项测试 `testDeterminism` 验证相同 DOM+options → 相同输出 |
| 公共 API 文档注释 | ✅ 全覆盖 |
| 非标准库依赖 | ✅ 零 |

### 4.5 设计偏差说明

| DESIGN 原文 | 实际实现 | 原因 |
|---|---|---|
| `XmlDocument.writeToString()` 直接挂在 DOM 类型上 | 通过 `writer` 包内 `extend XmlDocument` 植入 | 保持 DESIGN §4 的分层方向（`writer` → `dom`），避免循环依赖；对用户 API 无差别 |
| `XmlWriter` 复用 `XmlVisitor` 机制（§9.4） | M2 阶段直接递归下降 | `XmlVisitor` 属 M5；Writer 改写仅为内部重构，不影响外部契约 |

### 4.6 规模

- 本次迭代新增有效代码 ~680 行（生产 ~350 + 测试 ~330），远低于 1 万行预算
- 累计代码 ~2,250 行

---

## 5. 迭代 3（质量重构 + M3 Parser）——本次

### 5.1 存量质量重构（阶段 A）

按项目工程红线统一处理：

| 规则 | 落实 |
|---|---|
| 单源文件 ≤ 300 行 | `xml_element.cj` 457 → 145（拆 `xml_element_attrs.cj` / `xml_element_children.cj` / `xml_element_iters.cj`）；`dom_test.cj` 429 → 拆 `dom_document_test.cj` / `dom_element_test.cj`；`xml_writer.cj` 重构后 298 |
| 不得以下划线起名 | 全局替换 35 个 `_fooBar` 名为 `fooBar` / `fooRef` / `headChild` 等语义化名；`throw_` → `throwDom` |
| 降圈复杂度 | `XmlWriter.writeElementBlock` 拆 `chooseLayout` + `finishSelfClosing/Inline/Block`；`XmlElement.checkInsertable` 拆 `rejectSelfInsertion/IllegalKind/CrossDocument/AncestorCycle`；`escapeCdata` 内 while 拆 `appendWithCdataSplit`+`isCdataTerminatorAt` |
| 避免魔鬼数字/字符串 | `TAG_OPEN/CLOSE/SELF_CLOSE`、`PI_OPEN/CLOSE`、`COMMENT_OPEN/CLOSE`、`CDATA_OPEN/CLOSE/TERMINATOR_LEN`、`BOM_BYTE_0/1/2`、`DEFAULT_XML_DECLARATION_VALUE` / `DEFAULT_DECLARATION_VALUE` 等常量集中 |
| 公共 API 契约 | 完全不变；42/42 测试零修改通过 |

### 5.2 重构后的文件布局

```
src/dom/
  xml_element.cj           (145)  类、字段、kind、textContent、link/detach 工具
  xml_element_attrs.cj      (91)  extend：attribute/hasAttribute/setAttribute/removeAttribute
  xml_element_children.cj  (208)  extend：appendChild/removeChild/insertChildBefore/遍历
  xml_element_iters.cj      (84)  XmlChildIter / XmlChildElementIter
  xml_document.cj          (259)
  xml_node.cj              (125)
  xml_node_kind.cj          (27)
  xml_text.cj / xml_comment.cj / xml_attribute.cj / xml_declaration.cj / xml_unknown.cj
  dom_constants.cj          (10)  DEFAULT_DECLARATION_VALUE
  dom_document_test.cj     (160)  文档层测试
  dom_element_test.cj      (272)  元素层测试
src/writer/
  xml_writer.cj            (298)  含常量、排版决策、块/内联分派
  xml_write_options.cj / xml_sink.cj / dom_write_ext.cj / writer_test.cj
src/internal/
  text_escape.cj           (173)  escapeText/Attribute/Cdata + BOM 常量
```

### 5.3 M3 Parser（阶段 B）

#### 5.3.1 新增包结构

```
src/parser/
  xml_parse_options.cj       (53)  XmlParseOptions / XmlWhitespaceMode / DEFAULT_MAX_ELEMENT_DEPTH
  source_cursor.cj          (163)  SourceCursor + 字符分类工具
  entity_decoder.cj         (184)  decodeEntities + 数值/命名实体 + XML 1.0 Char 校验
  xml_parser.cj             (137)  XmlParser 类骨架 + 基础工具 (matchesChar/consumeExpected/readName)
  xml_parser_toplevel.cj    (158)  extend XmlParser：顶层分派 + 声明 / 注释 / CDATA / 未知节点
  xml_parser_element.cj     (194)  extend XmlParser：元素 / 属性 / 子节点 / 文本 / 闭合标签
  dom_parse_ext.cj           (27)  extend XmlDocument.parseString
  parser_test.cj            (286)  23 个测试用例
src/error/
  xml_parse_exception.cj     (25)  XmlParseException（包装 XmlError）
```

#### 5.3.2 功能覆盖

| 语法构造 | 状态 |
|---|---|
| 自闭合元素、开 / 闭标签、嵌套元素 | ✅ |
| 属性（单 / 双引号、实体还原、重复检查、`<` 禁用） | ✅ |
| XML 声明 `<?xml ... ?>`（保留原始 payload） | ✅ |
| 处理指令 `<?target ... ?>`（写入 `XmlUnknown`） | ✅ |
| 注释 `<!-- ... -->` | ✅ |
| CDATA `<![CDATA[ ... ]]>`（元素内合法；顶层报错） | ✅ |
| `<!DOCTYPE ...>` / `<!ENTITY ...>`（`XmlUnknown` 原样收容） | ✅ |
| 实体还原：`&amp; &lt; &gt; &quot; &apos; &#NN; &#xNN;` | ✅ |
| UTF-8 BOM：可选接受 / 拒绝 | ✅ |
| 空白策略：`Preserve` / `Collapse` | ✅ |
| 最大嵌套深度（默认 500，可配置） | ✅ |
| 根元素唯一性检查、空文档检查 | ✅ |
| 源位置 `SourcePos` 精确到行列 | ✅ |

#### 5.3.3 错误用例覆盖

- `EmptyDocument`
- `MismatchedElement`（`<a></b>` / EOF 未闭合）
- `InvalidText`（未知实体 / 顶层文本 / 顶层 CDATA / 不匹配的 `</...>`）
- `InvalidAttribute`（未引号化 / `<` 在属性内 / 未闭合 / 重复）
- `InvalidDeclaration`（未终止 PI）
- `InvalidComment`（未终止注释）
- `InvalidUnknownNode`（未终止 `<!` 块）
- `InvalidEncoding`（`acceptBom=false` 时遇到 BOM）
- `ElementDepthExceeded`（可配置 `maxElementDepth`）

#### 5.3.4 Round-trip

两条测试覆盖 "parse → write → 再 parse → 等价"：
1. `testParseRoundTripSimple`：普通元素/属性/文本
2. `testParseRoundTripWithEntities`：文本中含 `&`/`<`/`>` 等需转义字符

#### 5.3.5 质量门禁

| 门禁 | 状态 |
|---|---|
| `cjpm build` | ✅ 成功（仅 unused-warning，预期） |
| `cjpm test` | ✅ **65/65 通过**（20 DOM + 21 Writer + 23 Parser + 1 根包） |
| 单文件 ≤ 300 行 | ✅ 最长 298（`xml_writer.cj`） |
| 无下划线前缀标识符 | ✅ 全仓通过 |
| 无魔鬼字符串 / 数字 | ✅ 标签 / 实体分隔符 / BOM / 嵌套深度默认值均常量化 |
| 非标准库依赖 | ✅ 零 |

#### 5.3.6 设计偏差

| 原计划 | 实际 | 原因 |
|---|---|---|
| `XmlParser` 单文件包含所有解析流程 | 拆 `xml_parser.cj` + `xml_parser_toplevel.cj` + `xml_parser_element.cj` 三文件 | 单文件 300 行红线 + 绕开 cjc 1.0.5 下 "主类调用 extend 方法" 的解析限制 |
| 错误以 `Result<T, XmlError>` 返回 | `XmlParseException(XmlError, SourcePos)` 异常 | 减少每层签名噪声；对外 `parseString` 一处捕获点即可；`error` 字段保留枚举可模式匹配 |

### 5.4 M4 Query + Builder（迭代 4）

#### 5.4.1 新增包结构

```
src/query/
  xml_value_codec.cj         (37)  XmlValueCodec<T> 双向编解码接口
  builtin_codecs.cj         (140)  Int64/Int32/Float64/Bool/String codec + 单例 + trim/lower 工具
  xml_queryable.cj           (37)  XmlQueryable 接口（契约：cjc 1.0.5 跨包扩展可见性要求）
  element_query.cj          (118)  extend XmlElement <: XmlQueryable 实现
  query_test.cj             (186)  19 个 Query 测试用例
src/build/
  xml_element_builder.cj     (69)  XmlElementBuilder（立即落回 DOM，不形成平行结构）
  xml_document_builder.cj    (60)  XmlDocumentBuilder
  build_test.cj             (165)  10 个 Builder 测试用例（含 end-to-end round-trip）
src/parser/
  dom_parse_ext.cj          (46)  （扩展）新增顶层 parseXml() 函数，作为跨包稳定入口
```

#### 5.4.2 Query：`XmlValueCodec<T>` + extension

```cangjie
public interface XmlValueCodec<T> {
    func tryParse(text: String): ?T    // 失败返回 None，不抛异常
    func format(value: T): String
}
```

内置 codec 单例：`INT64_CODEC` / `INT32_CODEC` / `FLOAT64_CODEC` / `BOOL_CODEC` / `STRING_CODEC`。

`XmlQueryable` 接口 + `extend XmlElement <: XmlQueryable` 共 13 个方法：

| 方法 | 语义 |
|---|---|
| `attributeAs<T>(name, codec): ?T` | 读属性 + 泛型解析 |
| `intAttribute` / `int32Attribute` / `doubleAttribute` / `boolAttribute` | 常见标量的便捷短写 |
| `requiredAttribute(name): String` | 缺失抛 `XmlException` |
| `requiredAttributeAs<T>(name, codec): T` | 缺失或解析失败均抛 `XmlException` |
| `attributeOr<T>(name, codec, fallback): T` | 默认值兜底 |
| `childElement(name): ?XmlElement` | 按名字定位子元素 |
| `requiredChildElement(name): XmlElement` | 缺失抛 `XmlException` |
| `childElementText(name): ?String` / `childElementTextAs<T>` / `childElementTexts` | 子元素的文本读取（单值 / 解析 / 多值） |

#### 5.4.3 Builder：立即落回 DOM，不形成平行结构

```cangjie
let doc = XmlDocumentBuilder()
    .declaration()
    .root("catalog") { r =>
        r.element("book") { b =>
            b.attributeAs<Int64>("id", 1, INT64_CODEC)
             .text("SICP")
        }
    }
    .build()   // 返回的就是普通 XmlDocument
```

- `XmlDocumentBuilder`：`declaration` / `comment` / `root` / `build`；`declaration` 幂等。
- `XmlElementBuilder`：`attribute` / `attributeAs<T>` / `text(cdata?)` / `comment` / `element(name, configure)` / `build`。
- 所有写入**立即**落到底层 `XmlDocument`：不持有平行表示、不做事务性提交。用户在 `configure` lambda 里拿到 child builder，也是对同一棵真实 DOM 的引用。

#### 5.4.4 cjc 1.0.5 跨包扩展可见性问题

本次落地过程中发现一个关键规则：

> 跨包使用 `extend T { ... }`（不实现接口）的方法，调用方需要"导入该扩展的某个继承接口"——对纯追加方法的扩展这是**死锁**，因为没有接口可导入。
>
> 使用 `extend T <: I { ... }` 时，调用方**只能**看到 `I` 中声明的方法，其余 `public` 方法不可见。

处理方式：
- `query` 包：定义 `public interface XmlQueryable`，把所有 13 个公共方法签名声明在其中，然后 `extend XmlElement <: XmlQueryable` 实现之。
- `parser` 包：已有的 `extend XmlDocument.parseString` 跨包不可用；新增 **顶层** `parseXml(xml, options?)` 函数作为稳定跨包入口，`parseString` 保留作为同包/未来兼容入口。

#### 5.4.5 质量门禁

| 门禁 | 状态 |
|---|---|
| `cjpm build` | ✅ 成功 |
| `cjpm test` | ✅ **94/94 通过**（20 DOM + 21 Writer + 23 Parser + 19 Query + 10 Build + 1 根包） |
| 单文件 ≤ 300 行 | ✅ 最长仍为 298（`xml_writer.cj`） |
| 无下划线前缀标识符 | ✅ |
| 无魔鬼字符串 / 数字 | ✅ |
| 非标准库依赖 | ✅ 零 |

#### 5.4.6 E2E 回归

`testRoundTripBuildWriteParseQuery` 连接四条链路：**Builder → Writer → Parser → Query**，验证类型化属性（`Int64` / `Bool`）与子元素查询能完整穿越读写闭环。

### 5.5 M5 Visit（迭代 5）

#### 5.5.1 新增包结构

```
src/visit/
  xml_visitor.cj         (63)  XmlVisitor 接口（含默认 return true 实现）
  xml_walk_control.cj    (17)  XmlWalkControl 枚举
  walk.cj                (56)  walk(node, fn)：函数式前序遍历
  accept.cj              (65)  accept(node, visitor)：OO 访问者派发
  xml_visitable.cj       (32)  XmlVisitable 接口 + extend XmlNode 方法形式
  visit_test.cj         (288)  13 个测试用例
```

#### 5.5.2 `XmlVisitor`：经典 OO 风格

```cangjie
public interface XmlVisitor {
    func visitEnter(document: XmlDocument): Bool { true }
    func visitExit(document: XmlDocument): Bool  { true }
    func visitEnter(element: XmlElement): Bool   { true }
    func visitExit(element: XmlElement): Bool    { true }
    func visit(text: XmlText): Bool              { true }
    func visit(comment: XmlComment): Bool        { true }
    func visit(declaration: XmlDeclaration): Bool { true }
    func visit(unknown: XmlUnknown): Bool        { true }
}
```

与 tinyxml2 的差异：

- **不额外传属性链表**。tinyxml2 的 `visitEnter(XMLElement&, XMLAttribute*)`
  携带内部链表头指针；仓颉侧直接 `element.attributes()` 获取，签名干净。
- **统一带默认实现**。子类只实现关心的若干方法即可。
- 返回值语义保持对齐：`visitEnter` 返回 `false` 剪枝（不进入子树，不触发
  对应 `visitExit`）；叶子 `visit(...)` 返回 `false` 向上传播。

`accept(node, visitor)` 语义摘要：

| 情况 | 行为 |
|---|---|
| `visitEnter(容器)` 返回 `true` | 继续处理所有子节点，然后调用 `visitExit(容器)` |
| `visitEnter(容器)` 返回 `false` | 跳过子树 & **不**调用 `visitExit`，`accept` 返回 `true` 继续兄弟 |
| 某个子节点 `accept` 返回 `false` | 中止剩余兄弟处理，**仍然**调用 `visitExit`（RAII 对称），`accept` 返回 `false` |
| 叶子 `visit(...)` 返回 `false` | 本次 `accept` 返回 `false` |

#### 5.5.3 `walk` + `XmlWalkControl`：函数式风格

```cangjie
public enum XmlWalkControl {
    | Continue
    | SkipChildren
    | Stop
}

public func walk(node: XmlNode, visit: (XmlNodeKind) -> XmlWalkControl): Unit
```

相比 `XmlVisitor` 的 `Bool` 返回值（同一个 `false` 同时承担"剪枝"与"停机"两种
语义，调用方只能靠文档约定区分），`XmlWalkControl` 把两种意图**显式**区分：

- `Continue`：正常前序，下钻子节点。
- `SkipChildren`：当前节点不下钻，但继续处理兄弟。
- `Stop`：立即中止整次 `walk`（剩余节点一律不访问）。

#### 5.5.4 `XmlVisitable` 接口 + DOM 方法形式

除顶层 `accept(node, visitor)` / `walk(node, fn)` 外，本次还提供方法形式：

```cangjie
doc.accept(MyVisitor())
doc.walk { kind => Continue }
```

实现方式：`public interface XmlVisitable { func accept(...); func walk(...); }`
+ `extend XmlNode <: XmlVisitable`。这一做法再次套用"M4 踩过的坑"：cjc 1.0.5
要求跨包扩展的方法必须出现在其实现的接口中，否则对外不可见。

#### 5.5.5 关键实现约束 —— "lambda 捕获 `var`"

cjc 1.0.5 规则：

> 捕获了 `var`（可变变量）的 lambda 只能在定义处直接调用，不能作为值传递给
> 其它函数。

对 `walk`（接收 lambda 的顶层函数）这条规则几乎就是致命的——测试里没法写
`var count = 0; walk(doc) { _ => count++ ... }`。处理方式：

- 测试用一个 `class Counter { var n: Int64 = 0 }` 小封装绕过（class 字段不受
  "lambda 捕获 var"限制）。
- 文档里**显式**记录这一要点——这对最终用户也有价值，他们写
  聚合/计数逻辑时会遇到同样的坑。

#### 5.5.6 质量门禁

| 门禁 | 状态 |
|---|---|
| `cjpm build` | ✅ 成功 |
| `cjpm test` | ✅ **107/107 通过**（20 DOM + 21 Writer + 23 Parser + 19 Query + 10 Build + **13 Visit** + 1 根包） |
| 单文件 ≤ 300 行 | ✅ 最长 298（`xml_writer.cj`） |
| 无下划线前缀标识符 | ✅ |
| 无魔鬼字符串 / 数字 | ✅ |
| 非标准库依赖 | ✅ 零 |

### 5.6 M6 IO（迭代 6）

#### 5.6.1 新增包结构

```
src/io/
  xml_io_exception.cj    (26)  XmlIoException：IO 层异常
  load_xml.cj            (79)  loadXmlFromFile + parseXmlBytes
  save_xml.cj            (59)  saveXmlToFile + writeXmlToBytes
  file_xml_sink.cj       (96)  FileXmlSink <: XmlSink & Resource 流式写
  io_test.cj            (272)  12 个测试用例
```

#### 5.6.2 公共入口

```cangjie
// 文件 ↔ 文档
public func loadXmlFromFile(path: String): XmlDocument
public func loadXmlFromFile(path: String, options: XmlParseOptions): XmlDocument
public func saveXmlToFile(doc: XmlDocument, path: String): Unit
public func saveXmlToFile(doc: XmlDocument, path: String, options: XmlWriteOptions): Unit

// 字节 ↔ 文档
public func parseXmlBytes(bytes: Array<Byte>): XmlDocument
public func parseXmlBytes(bytes: Array<Byte>, options: XmlParseOptions): XmlDocument
public func writeXmlToBytes(doc: XmlDocument): Array<Byte>
public func writeXmlToBytes(doc: XmlDocument, options: XmlWriteOptions): Array<Byte>

// 流式 Sink（大文档 / 自组合 Writer）
public class FileXmlSink <: XmlSink & Resource {
    public init(path: String)
    public func write(text: String): Unit
    public func flush(): Unit
    public func close(): Unit
}
```

#### 5.6.3 错误模型

新增 `XmlIoException`，**与** `XmlParseException` 互不包装：

| 层 | 异常 | 触发场景 |
|---|---|---|
| IO | `XmlIoException(FileNotFound(path))` | 路径不存在 |
| IO | `XmlIoException(FileReadFailed(path, cause))` | 读取 `FSException`、非法 UTF-8 |
| IO | `XmlIoException(FileWriteFailed(path, cause))` | 写入 `FSException`、sink 已关闭 |
| 语法 | `XmlParseException(...)` | 已经读到字节但 XML 不合法 |

这一分层让调用方可以干净地分别处理"磁盘坏了"和"文件里的 XML 坏了"，无需查看内层 cause。`XmlError.FileNotFound` / `FileReadFailed` / `FileWriteFailed` 的枚举槽位自 M1 就已预留，这一次真正被点亮。

#### 5.6.4 关键实现决策

- **字符串暂存 vs 流式写盘**：`saveXmlToFile` 选择"先 `writeXmlToBytes` → 再 `File.writeTo` 一次性落盘"。好处是：序列化过程中的任何异常都**不会**留下半写入的文件，语义更像事务。需要内存友好的大文档场景，由 `FileXmlSink`（流式）按需选用——两条路径在 M6 并存而非互斥。
- **`FileXmlSink` 使用 `BufferedOutputStream<OutputStream>`** 包裹 `File`，避免每个 `write(text)` 都系统调用一次。资源语义走 `Resource + try-with-resource`：`close()` 先 `flush` 后关句柄，任一步异常都确保底层 `File` 被关。
- **`String.fromUtf8` 的失败路径**：非法 UTF-8 触发异常，被 `decodeUtf8(..)` 包装成 `XmlIoException(FileReadFailed)`，附带来源标签（文件路径或 `<bytes>` 字面量）。
- **与 parser 的可见性解耦**：M6 内部调用 `parseXml(xml, options)` 顶层函数（M4 为跨包访问引入的稳定入口），避免踩 `extend XmlDocument.parseString` 那条跨包编译不可见的老坑。
- **`Directory.create` 遇到已存在目录会抛 `FSException`**：测试夹具先 `exists(Path(...))` 再创建，否则二次运行就挂了。

#### 5.6.5 测试覆盖（12 用例）

`save/load` 往返、字节往返、compact 选项下的落盘文本不含换行、Unicode 文本内容往返、`FileNotFound`、非法 UTF-8 映射到 `FileReadFailed("<bytes>", ...)`、落盘后语法错误原样抛 `XmlParseException`、`FileXmlSink` 与 `StringXmlSink` 字节完全一致、sink 关闭后写入抛异常、不存在目录下构造 `FileXmlSink` 抛异常、端到端 `build → save → load → query` 联动。

#### 5.6.6 质量门禁

| 门禁 | 状态 |
|---|---|
| `cjpm build` | ✅ 成功 |
| `cjpm test` | ✅ **119/119 通过**（20 DOM + 21 Writer + 23 Parser + 19 Query + 10 Build + 13 Visit + **12 IO** + 1 根包） |
| 单文件 ≤ 300 行 | ✅ 最长 298（`xml_writer.cj`）；IO 包最长 272（`io_test.cj`） |
| 无下划线前缀标识符 | ✅ |
| 无魔鬼字符串 / 数字 | ✅（`TMP_ROOT` / `IN_MEMORY_SOURCE_LABEL` 均为 `const`） |
| 非标准库依赖 | ✅ 零 |

### 5.7 下一步候选

建议：**M8 回归 / 基准 / 发布**（跳过 M7 `Batch / Concurrency`，因为 CangjieXML 的目标是"贴合 tinyxml2 单线程 DOM"，并发优先级低于"补齐文档 / 基准 / 正式发布"）。理由：
1. 到 M6 为止，tinyxml2 公共 API 的等价覆盖度已接近 95%（仅剩"全局写出开关"和"编码声明驱动解码"两处被我们显式弃用 / 延后）。
2. 跨 6 次迭代的 119 个测试积累需要一次整合——基准数据、压力样例、正式 release 流程是"交付"层的最后一公里。
3. 并发模型（M7）与 DESIGN §4 的"DOM 不承诺线程安全"约定冲突，硬做会膨胀 API 面；更合适的处理是放到后续大版本。


### 5.8 M8 回归 + E2E（迭代 7）

#### 5.8.1 新增 `e2etest/` 端到端验收

- `e2etest/fixtures/generate.py` —— Python 用 `xml.etree` 生成 10 份典型 XML（目录/配置/深嵌套/Unicode/实体/混合内容/自闭合/RSS/无声明/CDATA）。
- `e2etest/python_probe/probe.py` —— Python 侧指纹 extractor，`xml.etree` 解析后规约成结构化 JSON。
- `e2etest/cangjie_probe/` —— 独立 cjpm 项目，通过 `path = "../.."` 引用本库，`loadXmlFromFile` 解析后导出同一份 JSON 形状。
- `e2etest/diff.py` —— 两侧 JSON 逐字段 diff，任何差异即 fail。
- `e2etest/run.sh` —— 一键入口：生成 → 构建仓颉 probe → 跑两端 → diff，任意步骤非 0 立即失败。
- `e2etest/README.md` —— 指纹设计、覆盖的 10 份 fixture、失败排查。

#### 5.8.2 指纹（fingerprint）

```
{ file, declaration_present, root, total_elements,
  elements: [{ path: "root[0]/child[i]/...", depth, name,
               attrs: <sorted>, text: <normalized direct text> }] }
```

- `path` 按"同名兄弟序号"编址——两端都算得出、稳定、可读。
- `attrs` 排序字典序——规避"保源序与否"的平台抖动。
- `text` 只取直接文本（Python = `text + 各孩子 tail`，仓颉 = 直接 `XmlText` 子节点 `.value` 拼接），空白规范化。
- CDATA 归一为普通文本——两侧都走文本分支。

#### 5.8.3 迭代中真实捕获到的 bug

**Bug**（**e2etest 自身**的 probe 代码，非主库）：`normalizeWhitespace` / `jsonEscape` 最初按字节遍历、把非特殊字节重造成 `Rune(UInt32(b))`，导致每个 UTF-8 续字节被当成独立码点，`算法导论` 被重写成 Latin-1 伪字符。**修复**：非特殊字节直接复制进 `ArrayList<Byte>`，最后 `String.fromUtf8` 一次性重建——通用规则：**按字节扫描的逻辑不应反向构造 `Rune`**。主库自身通过 10/10 指纹一致证明了 UTF-8 往返正确。

**顺手修**：`src/io/file_xml_sink.cj` 的 `import fastxml.dom.*` 属实未用，移除。

#### 5.8.4 最终质量门禁

| 门禁 | 状态 |
|---|---|
| `cjpm build` | ✅ |
| `cjpm test` | ✅ **119/119**（0 FAILED，0 ERROR） |
| `bash e2etest/run.sh` | ✅ `[PASS] all 10 fixtures produce identical fingerprints` |
| 单文件 ≤ 300 行 | ✅（`fingerprint.cj` 196 行为 e2e 最长；主库最长 298） |
| 无下划线前缀 | ✅ |
| 常量化 / 无魔鬼数字 | ✅ |
| 零运行时三方依赖 | ✅（e2etest 脚本仅用 Python 标准库） |

### 5.9 收尾

到此 M0–M6 全链路贯通，M8 的 e2e 验收作为"可用性证明"一次性通过。**M7 并发**与 DESIGN §4 的"DOM 不承诺线程安全"约定冲突，并非 tinyxml2 公共 API 的一部分，按约定跳过——后续若有专门的线程安全子类（`XmlThreadSafeDocument`）需求再另开分支。

CangjieXML 可以作为 **0.1.0** 候选发布版推进——tag 动作由维护方在 PR 合入后触发。
