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
| M3 | Parser | ✅ 已完成 | **迭代 3（本次，阶段 B）** |
| M4 | Query + Builder | ⏳ 未开始 | |
| M5 | Visit | ⏳ 未开始 | |
| M6 | IO + Error + Options 收口 | ⏳ 未开始 | 错误枚举骨架已预落位 |
| M7 | Batch / Concurrency | ⏳ 未开始 | |
| M8 | 回归 / 基准 / 发布 | ⏳ 未开始 | |

---

## 2. 按 tinyxml2 能力域的对照

tinyxml2 v11.0.0 公共 API 能力清单（按 DESIGN.md §3.2 归纳），以及当前 CangjieXML 实现状态：

| # | tinyxml2 能力 | CangjieXML 对应 | 状态 |
|---|---|---|---|
| 1 | DOM：`XMLDocument` / `XMLElement` / `XMLText` / `XMLComment` / `XMLDeclaration` / `XMLUnknown` / `XMLAttribute` | `dom.XmlDocument` / `XmlElement` / `XmlText` / `XmlComment` / `XmlDeclaration` / `XmlUnknown` / `XmlAttribute` | ✅ 已覆盖（M1） |
| 2 | 解析：`Parse(const char*)` / `LoadFile` / 流式 / 字节数组 | `XmlDocument.parseString` / `parseBytes` / `loadFile` | 🟡 `parseString` 已完成（M3）；`parseBytes` / `loadFile` 见 M6 |
| 3 | 序列化：`XMLPrinter` / `Print` / 紧凑 vs 格式化 | `writer.XmlWriter` + `XmlDocument/XmlElement.writeToString` | ✅ 已覆盖（M2） |
| 4 | 类型化属性：`IntAttribute` / `BoolAttribute` / `QueryXxx` | `query.*` 扩展 + `XmlValueCodec<T>` | ⏳ M4 |
| 5 | 访问者：`XMLVisitor` + `Accept` | `visit.XmlVisitor` + `walk()` | ⏳ M5 |
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

### 5.4 下一步候选

建议的下一次迭代：**M4 Query + Builder**。理由：
1. 读写闭环已完成，类型化访问（`IntAttribute` / `BoolAttribute` / `QueryXxx`）是 tinyxml2 用户最常触达的第二层 API；
2. `XmlValueCodec<T>` 在 DESIGN §7 已有详细签名，只需落地；
3. Builder DSL 是"锦上添花"的体验优化，可与 Query 并行引入。

