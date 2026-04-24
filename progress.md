# CangjieXML 开发进度

> 相对 [libxml2 v2.15.3](./.libxml2-2.15.3) 全量功能的实现情况。最新更新：迭代 11 结束（Phase 4c —— `reader.XmlReader`：拉式游标 API，基于 `XmlParser` 的 SaxEvent 流）。

---

## 总览

| Phase | 模块 | 对应 libxml2 | 状态 |
| --- | --- | --- | --- |
| 0 | 项目骨架 | — | ✅ 已完成 |
| 1 | `core` 基础设施 | `chvalid`、`xmlstring`、`buf`、`dict`、`hash`、`error`、`uri` | ✅ 已完成 |
| 2 | `encoding` + `io` | `encoding.c`、`xmlIO.c` | ✅ 已完成 |
| 3 | `parser` 词法 + 事件流 | `parser.c`、`parserInternals.c` | 🟢 词法 + 语法骨架已完成（Phase 3a+3b），容错模式 + 外部实体留待 Phase 3c |
| 4 | `tree` + `sax` + `reader` | `tree.c`、`SAX2.c`、`xmlreader.c` | 🟢 只读 DOM + DocumentBuilder（Phase 4a）+ 拉式 `XmlReader`（Phase 4c）完成；变更 API / `SaxHandler` 留待 Phase 4b / 4d |
| 5 | `writer` + `save` | `xmlwriter.c`、`xmlsave.c` | 🟢 `DocumentSerializer`（5a）+ `XmlWriter` 推式 API（5b）已完成；黄金对比 / 作用域跟踪留待后续 |
| 6 | `xpath` | `xpath.c` | ⬜ 未开始 |
| 7 | `regexp` + `pattern` + `dtd` | `valid.c`、`xmlregexp.c`、`pattern.c` | ⬜ 未开始 |
| 8 | `schema` | `xmlschemas.c`、`xmlschemastypes.c` | ⬜ 未开始 |
| 9 | `relaxng` + `schematron` | `relaxng.c`、`schematron.c` | ⬜ 未开始 |
| 10 | `catalog` + `xinclude` + `c14n` + `xpointer` | `catalog.c`、`xinclude.c`、`c14n.c`、`xpointer.c` | ⬜ 未开始 |
| 11 | `html` | `HTMLparser.c`、`HTMLtree.c` | ⬜ 未开始 |
| 12 | 工具链与发布 | `xmllint.c`、`xmlcatalog.c` | ⬜ 未开始 |
| 13 | 硬化与优化 | `runtest.c`、`fuzz/` | ⬜ 未开始 |

**粗略完成度**：核心功能 ≈ 45%（Phase 1 基础设施 + Phase 2 字符编解码 / I/O + Phase 3a 词法器 + Phase 3b XmlParser 骨架 + Phase 4a 只读 DOM + DocumentBuilder + Phase 4c XmlReader + Phase 5a 基础序列化器 + Phase 5b 推式 XmlWriter；不含容错模式 / 外部实体 / DOM 变更 API / SaxHandler / 验证器 / 工具链）。

---

## 已实现（迭代 1 — Phase 0 + Phase 1）

### Phase 0：项目骨架

- [x] 顶层 `cjpm.toml`
- [x] `cangjie-format.toml` 格式化配置
- [x] `.gitignore`
- [x] `README.md`（项目简介、构建、已实现模块说明）
- [x] `progress.md`（本文件）
- [x] `src/cangjie_xml.cj` 顶层门面占位

### Phase 1：`core` 基础设施模块（完整）

#### 对应 libxml2 `chvalid.c`
- [x] XML 1.0 / XML 1.1 `Char` 合法区间
- [x] `NameStartChar` / `NameChar` 区间（与 W3C XML 1.0 第 4 / 4e 产生式对齐）
- [x] `isXmlWhitespace` / `isPubidChar`
- [x] XML 1.1 "受限字符"（`isXml11RestrictedChar`）
- [x] 整串校验辅助：`isValidName` / `isValidNcName` / `isValidXmlString`
- [x] 区间表二分查找（`contains`）

#### 对应 libxml2 `buf.c`
- [x] `GrowableBuffer`（字节缓冲，支持按 UTF-8 写码点）
- [x] `BoundedBuffer`（带上限检查，抛 `LimitExceeded`）

#### 对应 libxml2 `xmlstring.c`
- [x] `bytesToString`（非法 UTF-8 转 `XmlException`）
- [x] `escapeXml`（文本 / 属性双模式）
- [x] `normalizeWhitespace`（属性值第二阶段归一）
- [x] `normalizeNewlines`（XML 1.0/1.1 行尾归一）
- ⬜ 其余 `xmlStr*` 系列（大多被仓颉原生 `String` 直接覆盖，不再复刻）

#### 对应 libxml2 `dict.c` / `hash.c`
- [x] `NameTable`（单线程 intern 池）
- [x] `ConcurrentNameTable`（`ConcurrentHashMap` 版本）
- ⬜ libxml2 的内存池特化（仓颉 GC 接管，无需）

#### 新增（libxml2 无直接对应，属于现代化重设计）
- [x] `QName`：不可变 `struct`，`(localName, uri)` 语义等价；替代 libxml2 的"前缀拼接字符串"方案
- [x] `combineHash`：避免 Int64 乘法溢出的哈希混合函数

#### 对应 libxml2 `error.c`
- [x] `Position`（源码定位）
- [x] `Severity`（Warning / Error / Fatal）
- [x] `XmlError`（分支枚举，10 类）
- [x] `XmlException <: Exception`
- [x] `ErrorCollector` 接口
- [x] `ListErrorCollector` / `SilentErrorCollector` 两份默认实现

#### 对应 libxml2 `uri.c`
- [x] `Uri` 不可变值对象
- [x] RFC 3986 解析（scheme / authority / path / query / fragment）
- [x] RFC 3986 §6 归一化（scheme / host 大小写、remove-dot-segments、IPv6 bracket 保持）
- [x] RFC 3986 §5.3 相对参考解析（`resolve(base)`）
- [x] 组件回装（`toString`）往返
- [x] 通过 RFC 3986 §5.4.1 正常示例 23 条 + §5.4.2 异常示例 8 条测试
- ⬜ Windows 盘符兼容开关（`windowsPathCompat`，后续按需开）
- ⬜ 百分号解码 / 重新编码的严格 %HH 校验（当前仅做组件切分，不改动原始字节）

### 测试

- [x] 36 个单元测试，`cjpm test` 全绿
- [x] 覆盖范围：字符类、缓冲、字符串工具、intern 池、QName 语义、错误模型、URI 全部 API
- ⬜ `cjcov` 覆盖率报告（SDK 中含 `cjcov`，后续迭代接入 CI）
- ⬜ W3C `test/URI/` 黄金对比（libxml2 自带的 URI 用例集，下一迭代引入 `testkit`）

---

## 已实现（迭代 2 — Phase 2 前半：`encoding` 模块）

### 对应 libxml2 `encoding.c`

#### 基础类型
- [x] `DecodeStatus`（`Success` / `NeedMoreInput` / `InvalidBytes(offset)`）
- [x] `EncodeStatus`（`Success` / `Unmappable(index, codepoint)`）
- [x] `DecodeResult` / `EncodeResult` 结构体
- [x] `BomKind` 枚举（UTF-8 / UTF-16 LE/BE / UTF-32 LE/BE）+ 字节长度 / 编码名查询
- [x] `encodingError` 诊断辅助

#### BOM 探测
- [x] `detectBom(bytes)`：严格按 BOM 字节签名（UTF-32 LE 签名覆盖 UTF-16 LE 的优先级已处理）
- [x] `heuristicDetect(bytes)`：W3C XML §F 附录 `<?xml` 对齐模式启发式

#### 解码器基类
- [x] `abstract class Decoder`（`name` 属性、流式 `decode(bytes, start, end, endOfInput)`、`reset()`、一次性 `decodeAll()`）
- [x] 状态保留：子类可携带"半截序列"跨分片继续解码

#### 内置解码器
- [x] `Utf8Decoder`（RFC 3629：4 字节上限、拒绝超长 / 代理 / > U+10FFFF）
- [x] `Utf16Decoder` LE + BE（严格代理对，跨片状态含悬挂的高位代理 + 1 字节 pending）
- [x] `Utf32Decoder` LE + BE（拒绝代理 / 越界码点，4 字节原子消费）
- [x] `SingleByteDecoder` 通用单字节解码器 + 映射表：
  - [x] US-ASCII（高 128 位全未定义）
  - [x] ISO-8859-1 / -2 / -3（含未定义位）/ -4 / -5（西里尔）/ -9（Latin-5 土耳其）/ -15（Latin-9，含 €）

#### 编码器基类
- [x] `abstract class Encoder`（`name` / `writesBom` / `encode(text)` / `encodeAll()`）

#### 内置编码器
- [x] `Utf8Encoder`（无状态，底层 UTF-8 字节直出）
- [x] `Utf16Encoder` LE + BE（可选 BOM 输出，代理对生成）
- [x] `SingleByteEncoder` 通用单字节编码器（US-ASCII / ISO-8859-1 / -2 / -15）
- ⬜ UTF-32 编码器（libxml2 本身不在输出侧暴露，可按需补）
- ⬜ ISO-8859-6/7/8/10..14 编码器（解码器亦未覆盖，后续按需补齐；差异表即可）

#### 编码注册表
- [x] `EncodingRegistry` 按规范名 / 别名查找解码器与编码器
- [x] `normalize(name)` 归一化：小写 + 去 `-` / `_` / 空格；`UTF-8` / `utf_8` / `utf8` 等价
- [x] `registerDecoder` / `registerEncoder` / `registerAlias` 自定义注册
- [x] `defaultRegistry()` 预注册所有内置编码 + 常用别名（`ascii`、`latin-1`、`latin-5`、`cyrillic` 等）

### 测试（`cjpm test` 82/82 全绿）

新增 46 个测试用例，覆盖：
- BOM 探测（UTF-8 / UTF-16 LE/BE / UTF-32 LE/BE 优先级、无 BOM、启发式）
- UTF-8 ASCII 快路径 / 多字节往返 / 拒绝超长 / 拒绝代理 / 截断 EOF / 流式分片 / 孤立续字节
- UTF-16 LE+BE 往返 / BOM 前缀字节验证 / 代理对 / 孤立低代理 / 悬挂高代理 / 奇数字节 EOF / 流式
- UTF-32 LE+BE 基础 / 多字节 / 补充平面 / 拒绝代理 / 拒绝越界 / 非 4 倍数 / 流式
- US-ASCII / ISO-8859-1 / -2 / -3 / -5 / -9 / -15 解码与编码、错误字节定位、不可映射码点诊断
- `EncodingRegistry` 名字归一 / 按别名查找 / 工厂隔离（同名多实例状态独立）

---

## 已实现（迭代 3 — Phase 2 后半：`io` 模块）

### 对应 libxml2 `xmlIO.c`（不含 nano-HTTP / FTP）

#### 输入侧
- [x] `interface IoSource <: Resource`：`read(buffer) -> Int64`、`baseUri`、`encodingHint`
- [x] `MemorySource`：字节数组零拷贝源
- [x] `StringSource`：把 `String` 当 UTF-8 字节源（自动设置 `encodingHint = "utf-8"`）
- [x] `StreamSource`：包装任意 `std.io.InputStream`，`owned` 标志控制级联关闭
- [x] `FileSource`：基于 `std.fs.File(path, OpenMode.Read)`，自动设置 `baseUri = path`，错误统一包装为 `XmlException(IoError)`
- [x] `readAll(source)` 便利函数

#### 输出侧
- [x] `interface IoSink <: Resource`：`write(bytes)`、`flush()`
- [x] `MemorySink`：累积到 `GrowableBuffer`；`toBytes()` 取快照
- [x] `StreamSink`：包装 `std.io.OutputStream`
- [x] `FileSink`：`OpenMode.Write`（截断）或 `OpenMode.Append`

#### 装饰器
- [x] `BufferedSink`：固定容量缓冲（默认 4096）；大块旁路直写、小块聚合；`close` 自动 flush；`owned` 控制级联
- [x] `IndentingSink`：命令式缩进 API（`increaseIndent` / `decreaseIndent` / `writeIndent`），可配置 `indentUnit` 与 `newline`；字节 pass-through 不扫描内容（语义判断交给上层 writer）
- [x] `EncodingSink`：UTF-8 输入 → 任意目标编码输出，复用上一迭代 `encoding.Decoder` + `Encoder`；支持流式分片（拼接半截 UTF-8）；可选首字节 BOM；`flush()` 对半截 UTF-8 抛 `IoError`

#### 编码感知输入
- [x] `DecodingSource`：在 `IoSource` 之上再包一层，提供字符级读取
  - 探测优先级：**显式 encoding > BOM > `encodingHint` > UTF-8 默认**
  - 自动跳过 BOM 字节
  - 暴露 `detectedEncoding: String` / `bom: ?BomKind` 供 parser 查询
  - `readChunk()` 流式、`readAllAsString()` 一次性
  - 非法字节抛 `XmlException(EncodingError)` 附带字节偏移

### 测试（`cjpm test` 119/119 全绿）

新增 37 个测试用例（io 子包），覆盖：
- MemorySource 分片读 / close 后 EOF / encodingHint 传递
- StringSource UTF-8 字节序一致性
- StreamSource 包裹 `ByteBuffer`
- MemorySink 累积 / close 后写拒绝
- StreamSink 向 `ByteBuffer` 写 + flush
- BufferedSink：缓冲聚合、满时自动 flush、大块旁路、close 级联、capacity 下限校验
- IndentingSink：pass-through、`writeIndent` 换行 + N 级缩进、嵌套层次、自定义换行符（`\r\n`）
- EncodingSink：UTF-8 身份、UTF-16 BE 有/无 BOM、ASCII 不可映射、流式三片解码、flush 时半截 UTF-8 检测、close 级联
- DecodingSource：UTF-8 无/有 BOM、UTF-16 LE/BE BOM、UTF-32 LE BOM 优先于 UTF-16 LE、`encodingHint` 生效、显式 > hint、空输入 EOF、非法字节抛异常、`ownedSource` 级联关闭

---

按 `ROADMAP.md` 顺序依次推进：

- ✅ ~~Phase 2 `io`：`IoSource` / `IoSink` / `BufferedSink` / `IndentingSink` / `EncodingSink`~~
- ✅ ~~Phase 3a `parser` 词法层：`RuneReader` / `Token` / `Lexer`~~
- ✅ ~~Phase 3b `parser` 语法层：`XmlParser` → `Iterator<SaxEvent>`（元素栈、命名空间、属性聚合、预定义实体、深度 / 扩展限制、`ParserOptions` 基础字段、`NameTable` intern）~~
- 🟡 Phase 3c `parser` 补完：`EntityResolver` 加载外部实体 + `recover=true` 容错路径 + W3C `xmltest` 黄金对比
- Phase 4 `tree` / `sax` / `reader`：`sealed interface Node` + DOM / SAX / XmlReader
- Phase 5 `writer` / `save`：`XmlWriter` + `DocumentSerializer`
- Phase 6 `xpath`：XPath 1.0 引擎
- Phase 7 `regexp` / `pattern` / `dtd`
- Phase 8 `schema`：XML Schema 1.0（8a 骨架 → 8b 全功能）
- Phase 9 `relaxng` / `schematron`
- Phase 10 `catalog` / `xinclude` / `c14n` / `xpointer`
- Phase 11 `html`
- Phase 12 `facade` + `tools/xmllint` + `tools/xmlcatalog`
- Phase 13 硬化与性能优化

---

## 已实现（迭代 4 — Phase 3a：`parser` 词法层）

> Phase 3 在 `ROADMAP.md` 中是一个巨型阶段（词法 + 语法 + 命名空间 + 实体 + SaxEvent + 容错）。按 DESIGN §7 建议自顶向下切片，本迭代交付 **Phase 3a：词法器**；Phase 3b（`XmlParser` → `Iterator<SaxEvent>`）留给下一迭代。

### 对应 libxml2 `parser.c` / `parserInternals.c` 的词法路径

#### `RuneReader`（对应 libxml2 `xmlCurrentChar` / `xmlNextChar` / 输入推进）
- [x] 在迭代 3 的 `DecodingSource` 之上提供字符级读取，无感知底层字节编码
- [x] 位置追踪：1-based `line` / `column`、字符级 `byteOffset`
- [x] XML 1.0 换行归一化：`#xD #xA → #xA`、`#xD → #xA`
- [x] XML 1.1 额外归一化：`#x85 → #xA`、`#x2028 → #xA`、`#xD #x85 → #xA`
- [x] `peek(k)` 支持 0..3 回看（用于 `]]>` / `-->` / `?>` 多字符分隔符探测）
- [x] `consumeIf(rune)` / `consumeIfStr(str)` 词法器高频路径
- [x] 生命周期：`ownedSource` 控制 `close()` 是否级联到 `DecodingSource`

#### `Token`（libxml2 通过 SAX 回调直出，无此中间层）
本项目显式引入词法 Token 以利于单元测试、容错恢复与 Parser 层解耦：
- [x] 元素：`ElementOpenStart(name)` / `ElementOpenEnd` / `ElementSelfClose` / `ElementClose(name)`
- [x] 属性：`AttrName` / `AttrEq` / `AttrValueStart(quote)` / `AttrValueChunk(text)` / `AttrValueEnd(quote)`
- [x] XML 声明：`XmlDeclStart` / `XmlDeclEnd`（夹在中间的属性复用属性 token）
- [x] 文本 / CDATA / 注释 / PI：`Text` / `CDataSection` / `Comment` / `ProcessingInstruction(target, data)`
- [x] DOCTYPE 头：`DoctypeStart(name)` / `DoctypeEnd`（ExternalID 与内部子集留给 Parser 层）
- [x] 引用：`EntityRef(name)` / `CharRef(codepoint)`（词法层**不**展开实体）
- [x] `Eof` 哨兵
- [x] 每个 Token 携带精确起始 `Position`

#### `Lexer`（对应 libxml2 词法路径）
- [x] 实现 `Iterator<Token>`，支持流式惰性消费
- [x] 状态机手写（非正则）：`readContent` / `readTagLike` / `readBangConstruct` / `readPiOrXmlDecl` / `readInsideOpenTag` / `readAttrValueFragment`
- [x] `Lexer.fromString(s)` 测试便利构造
- [x] 词法级 well-formedness 校验：
  - `]]>` 不允许出现在文本（仅 CDATA 内合法）
  - 注释内不允许 `--`，且必须以 `-->` 结束（不允许 `--->`）
  - PI target 不能是 `xml` / `XML` / 任意大小写变体
  - XML 声明只能出现在文档最开始（之前不能有非空白字符或其他元素）
  - 属性值中直接出现 `<` 非法
  - 字符引用的数字必须落在 Unicode 范围内且是合法的 XML 字符
  - 实体引用必须以 `;` 结尾
  - 所有字符都必须满足 `isXmlChar`（按当前 `XmlVersion`）
- [x] 属性值 §3.3.3 归一：`#x9` / `#xA`（已由 RuneReader 归一）在 chunk 中折叠为 `#x20`
- [x] 精确到字符的错误 `Position`，错误包装为 `XmlException(XmlError.*)`
- [x] DOCTYPE 头部粗略跳过（识别内部子集括号 + 带引号字符串中的 `>`），不误把其中的 `<` / `&` 当作元素 / 实体

### 存量内容复盘（按用户要求）

本迭代直接复用了以下已有模块，**经评估均为最优实现，无需重构**：

| 存量模块 | 复用点 | 结论 |
| --- | --- | --- |
| `core.char_valid` | `isXmlChar` / `isNameStartChar` / `isNameChar` / `isXmlWhitespace` | 区间表 + 二分，O(log n)，零分配，最优 |
| `core.error` | `Position` / `XmlError.*` / `XmlException` | 分支枚举 + `match`，语义与错误位置已经对齐 libxml2 |
| `core.buffer` 的 `StringBuilder` | 词法 token 累积 | 直接用仓颉核心 `StringBuilder`，已经优化 |
| `io.DecodingSource` | RuneReader 底层字符源 | 在迭代 3 就是按本迭代需求设计，契约精准吻合 |

唯一观察到的小缺口：`progress.md` 之前的"完成度"估算一直是 13%，本迭代更新到 18%。

### 测试（`cjpm test` 166/166 全绿）

新增 47 个测试用例（parser 子包）：

**RuneReader（14 个）**：
- `peek` / `advance` / `peek(k)` 回看 / EOF 语义
- 单行字符列号推进、多行跨 `\n` 的 `(line, column)`
- CR + LF 归一、孤立 CR 归一、CRLF 行号
- XML 1.1 NEL (U+0085) 归一、Line Separator (U+2028) 归一
- XML 1.0 下 NEL 保留为普通字符（反向验证）
- `consumeIf` / `consumeIfStr` 成功 + 失败（不消费回滚）
- 非 ASCII Unicode（中文）
- `characterOffset` 累加
- `ownedSource` 级联 close

**Lexer（33 个）**：
- 元素：空自闭合、开闭标签、嵌套、带冒号+连字符的名字
- 属性：双引号、单引号、多属性、实体引用、字符引用（十进制 + 十六进制）、换行/TAB 折叠
- 文本、CDATA（含内部伪 XML）、注释（拒绝 `--`、未闭合）
- PI（正常 target、目标为 `xml` 拒绝）
- XML 声明（完整属性列表）、强制首位出现（反向验证）
- DOCTYPE：简单 / 内部子集 `[...]` / 带 `>` 的引号字符串
- 错误：字符引用越界 / 空 / 指向非法 XML 字符、实体引用缺 `;`、未闭合注释 / CDATA / 元素、属性值内 `<`、文本内 `]]>`
- 位置追踪（行列精确到多行中的嵌套元素）
---

## 已实现（迭代 5 — Phase 3b：`parser` 语法层 / SAX 事件流）

对应 libxml2 `parser.c` 主解析函数 + `SAX2.c` 的回调聚合。架构完全重写为
`Iterator<SaxEvent>`（`DESIGN.md §7.1`），消除 libxml2 推/拉双实现的行为偏差。

### 新增类型

| 类型 | 位置 | 作用 |
| --- | --- | --- |
| `SaxEvent` | `parser/sax_event.cj` | 统一事件枚举（StartDocument / EndDocument / StartElement / EndElement / Characters / Cdata / CommentEvent / Pi / Doctype / EntityReference / ParseError）|
| `XmlDecl` | `parser/sax_event.cj` | XML 声明三元组（version / encoding / Standalone） |
| `Attribute` | `parser/sax_event.cj` | 解析后的属性（QName + 展开后值 + 位置 + `isNamespaceDeclaration`） |
| `Standalone` | `parser/sax_event.cj` | 三态枚举（`Yes` / `No` / `Unspecified`） |
| `NsContext` | `parser/ns_context.cj` | **不可变持久化**命名空间栈，规避 libxml2 `xmlNs*` 指针相关 CVE |
| `EntityResolver` / `DefaultEntityResolver` / `MapEntityResolver` / `EntityResolution` | `parser/entity_resolver.cj` | 实体解析接口 + 仅预定义实体的默认实现（XXE 防护） |
| `ParserOptions` | `parser/parser_options.cj` | 结构体 + 命名参数（取代 libxml2 位掩码） |
| `XmlParser` | `parser/xml_parser.cj` | `Iterator<SaxEvent>`，从 `Lexer` 产出 SAX 事件 |

### 关键特性

- **文档骨架恒常化**：无论源文档是否带 `<?xml ?>`，事件流恒以 `StartDocument` 开始、`EndDocument` 结束。
- **XML 声明属性顺序校验**：`version` / `encoding` / `standalone` 按 W3C 规定的顺序出现；`encoding` 值走 `[A-Za-z][A-Za-z0-9._-]*` 语法白名单。
- **元素栈 + 开闭匹配**：开闭标签的词法名必须完全一致；根元素唯一；未闭合元素 EOF 触发 `UnexpectedEof`。
- **属性聚合**：从 Lexer 的 `AttrName` + `AttrValueStart/Chunk/EntityRef/CharRef/End` 序列里组装 `Attribute`，展开预定义实体 + 字符引用 + `MapEntityResolver` 的用户实体。
- **命名空间组装**（W3C Namespaces 1.0 / 1.1 严格对齐）：
  - 元素 / 属性 QName 一次性解析出 `uri`；
  - 默认命名空间**不**应用于属性（§6.2）；
  - `xml` 前缀硬绑定到 `http://www.w3.org/XML/1998/namespace`；`xmlns` 前缀硬绑定到 `http://www.w3.org/2000/xmlns/`；
  - 拒绝 `xmlns:xml=` 绑定到非 XML NS、拒绝 `xmlns:xmlns=...`、拒绝其他前缀绑定 XML / xmlns 命名空间 URI；
  - 属性唯一性按**扩展名**（URI + localName）去重：允许 `a:x` 与 `b:x` 映射到不同 URI 时共存，相同 URI 时拒绝。
- **事件合并**：连续 Text / CharRef / 展开后的 EntityRef 合并为单个 `Characters` 事件；CDATA 独立为 `Cdata`（语义保留）。
- **深度限制 / Billion Laughs 防护**：元素嵌套超 `maxDepth` / 实体展开总字符超 `maxEntityExpansion` → `XmlError.LimitExceeded`。
- **选项**：
  - `substituteEntities = false` → 透传 `EntityReference(name)` 事件；
  - `keepBlanks = false` → 跳过仅空白的 `Characters`；
  - `nameTable` 配置后，元素 / 属性的 local + prefix 走 intern 池，对大文档降低内存占用；
  - `entityResolver` 注入自定义实体（预定义 5 个永远优先，用户不得覆盖，W3C §4.6）。

### 存量复盘（按用户要求）

| 模块 | 复用方式 | 结论 |
| --- | --- | --- |
| `core.qname.QName` | 元素 / 属性名一次性构造 `(local, prefix, uri)` | 已最优，无需重构 |
| `core.name_table.NameTable` | `ParserOptions.nameTable` 直接 intern | 已最优 |
| `core.error.XmlError.{Malformed,LimitExceeded,NamespaceError,UnexpectedEof}` | 全部错误枚举变体已足够 | 已最优 |
| `parser.Token` | 粒度刚好适配聚合路径（`AttrValueChunk` / `EntityRef` / `CharRef` 分片） | 已最优，无需改动 |
| `parser.Lexer` | 直接以 `Iterator<Token>` 喂给 `XmlParser` | 已最优 |
| `std.collection.ArrayStack` | 元素栈 + NsContext 栈 | 使用 `add / remove / peek` 契约 |

**无需重构存量**。本次仅在 `progress.md` / `README.md` 中把完成度估算从 18% 更新到 26%。

### 测试（新增 57 个用例，`cjpm test` 223/223 全绿）

- `sax_event_test.cj`（6）：`XmlDecl` / `Attribute` / `SaxEvent.toString()` / `position()` / `Standalone` 等值。
- `ns_context_test.cj`（8）：root / push / shadow / unbind / 不可变性 / bindings / xmlns 硬绑定。
- `entity_resolver_test.cj`（4）：预定义 / 未知 / 用户扩展 / 预定义优先。
- `xml_parser_test.cj`（39）：骨架、嵌套、自闭合、属性展开、引号两种、多根元素拒绝、开闭错配、EOF、XML 声明所有约束、命名空间所有规则、连续文本合并、CDATA 独立、Comment / PI / DOCTYPE、`keepBlanks` / `substituteEntities` / `maxDepth` / `maxEntityExpansion` / `nameTable` / 自定义 `EntityResolver`、非空白根外文本、前导 Comment/PI、两前缀同 URI 重复、两前缀异 URI 允许。

---

## 与 `DESIGN.md` / `ROADMAP.md` 的对齐调整

### 新增类型

| 类型 | 位置 | 作用 |
| --- | --- | --- |
| `SaxEvent` | `parser/sax_event.cj` | 统一事件枚举（StartDocument / EndDocument / StartElement / EndElement / Characters / Cdata / CommentEvent / Pi / Doctype / EntityReference / ParseError）|
| `XmlDecl` | `parser/sax_event.cj` | XML 声明三元组（version / encoding / Standalone） |
| `Attribute` | `parser/sax_event.cj` | 解析后的属性（QName + 展开后值 + 位置 + `isNamespaceDeclaration`） |
| `Standalone` | `parser/sax_event.cj` | 三态枚举（`Yes` / `No` / `Unspecified`） |
| `NsContext` | `parser/ns_context.cj` | **不可变持久化**命名空间栈，规避 libxml2 `xmlNs*` 指针相关 CVE |
| `EntityResolver` / `DefaultEntityResolver` / `MapEntityResolver` / `EntityResolution` | `parser/entity_resolver.cj` | 实体解析接口 + 仅预定义实体的默认实现（XXE 防护） |
| `ParserOptions` | `parser/parser_options.cj` | 结构体 + 命名参数（取代 libxml2 位掩码） |
| `XmlParser` | `parser/xml_parser.cj` | `Iterator<SaxEvent>`，从 `Lexer` 产出 SAX 事件 |

### 关键特性

- **文档骨架恒常化**：无论源文档是否带 `<?xml ?>`，事件流恒以 `StartDocument` 开始、`EndDocument` 结束。
- **XML 声明属性顺序校验**：`version` / `encoding` / `standalone` 按 W3C 规定的顺序出现；`encoding` 值走 `[A-Za-z][A-Za-z0-9._-]*` 语法白名单。
- **元素栈 + 开闭匹配**：开闭标签的词法名必须完全一致；根元素唯一；未闭合元素 EOF 触发 `UnexpectedEof`。
- **属性聚合**：从 Lexer 的 `AttrName` + `AttrValueStart/Chunk/EntityRef/CharRef/End` 序列里组装 `Attribute`，展开预定义实体 + 字符引用 + `MapEntityResolver` 的用户实体。
- **命名空间组装**（W3C Namespaces 1.0 / 1.1 严格对齐）：
  - 元素 / 属性 QName 一次性解析出 `uri`；
  - 默认命名空间**不**应用于属性（§6.2）；
  - `xml` 前缀硬绑定到 `http://www.w3.org/XML/1998/namespace`；`xmlns` 前缀硬绑定到 `http://www.w3.org/2000/xmlns/`；
  - 拒绝 `xmlns:xml=` 绑定到非 XML NS、拒绝 `xmlns:xmlns=...`、拒绝其他前缀绑定 XML / xmlns 命名空间 URI；
  - 属性唯一性按**扩展名**（URI + localName）去重：允许 `a:x` 与 `b:x` 映射到不同 URI 时共存，相同 URI 时拒绝。
- **事件合并**：连续 Text / CharRef / 展开后的 EntityRef 合并为单个 `Characters` 事件；CDATA 独立为 `Cdata`（语义保留）。
- **深度限制 / Billion Laughs 防护**：元素嵌套超 `maxDepth` / 实体展开总字符超 `maxEntityExpansion` → `XmlError.LimitExceeded`。
- **选项**：
  - `substituteEntities = false` → 透传 `EntityReference(name)` 事件；
  - `keepBlanks = false` → 跳过仅空白的 `Characters`；
  - `nameTable` 配置后，元素 / 属性的 local + prefix 走 intern 池，对大文档降低内存占用；
  - `entityResolver` 注入自定义实体（预定义 5 个永远优先，用户不得覆盖，W3C §4.6）。

### 存量复盘（按用户要求）

| 模块 | 复用方式 | 结论 |
| --- | --- | --- |
| `core.qname.QName` | 元素 / 属性名一次性构造 `(local, prefix, uri)` | 已最优，无需重构 |
| `core.name_table.NameTable` | `ParserOptions.nameTable` 直接 intern | 已最优 |
| `core.error.XmlError/Malformed/LimitExceeded/NamespaceError/UnexpectedEof` | 全部错误枚举变体已足够 | 已最优 |
| `parser.Token` | 粒度刚好适配聚合路径（`AttrValueChunk` / `EntityRef` / `CharRef` 分片） | 已最优，无需改动 |
| `parser.Lexer` | 直接以 `Iterator<Token>` 喂给 `XmlParser` | 已最优 |
| `std.collection.ArrayStack` | 元素栈 + NsContext 栈 | 使用 `add/remove/peek` 契约 |

**无需重构存量**。本次仅在 `progress.md` / `README.md` 中把完成度估算从 18% 更新到 26%。

### 测试（新增 57 个用例，`cjpm test` 223/223 全绿）

- `sax_event_test.cj`（6）：`XmlDecl` / `Attribute` / `SaxEvent.toString()` / `position()` / `Standalone` 等值。
- `ns_context_test.cj`（8）：root / push / shadow / unbind / 不可变性 / bindings / xmlns 硬绑定。
- `entity_resolver_test.cj`（4）：预定义 / 未知 / 用户扩展 / 预定义优先。
- `xml_parser_test.cj`（39）：骨架、嵌套、自闭合、属性展开、引号两种、多根元素拒绝、开闭错配、EOF、XML 声明所有约束、命名空间所有规则、连续文本合并、CDATA 独立、Comment / PI / DOCTYPE、`keepBlanks` / `substituteEntities` / `maxDepth` / `maxEntityExpansion` / `nameTable` / 自定义 `EntityResolver`、非空白根外文本、前导 Comment/PI、两前缀同 URI 重复、两前缀异 URI 允许。

- `xml_parser_test.cj`（39）：骨架、嵌套、自闭合、属性展开、引号两种、多根元素拒绝、开闭错配、EOF、XML 声明所有约束、命名空间所有规则、连续文本合并、CDATA 独立、Comment / PI / DOCTYPE、`keepBlanks` / `substituteEntities` / `maxDepth` / `maxEntityExpansion` / `nameTable` / 自定义 `EntityResolver`、非空白根外文本、前导 Comment/PI、两前缀同 URI 重复、两前缀异 URI 允许。



本迭代为适配 `cjpm 1.0.5` 的实际能力，对设计做了以下小幅调整（均以"提升产品质量与可行性"为目标导向）：

1. **包布局**：`DESIGN.md §4` 原方案是 `cjpm` workspace + `packages/<name>/`；`cjpm 1.0.5` 未提供 workspace 子命令，改为 **单模块 + `src/<name>/` 子包** 布局，各包导入路径变为 `cangjie_xml.<name>.*`。语义等价，后续阶段沿用。
2. **`Byte` 构造**：`Byte` 作为 `UInt8` 的类型别名在当前 SDK 下不能作为构造函数调用，内部统一写作 `UInt8(...)`。公共 API 签名仍使用 `Byte` 类型别名。
3. **哈希混合**：Cangjie 的 `*` 默认做溢出检查，散列函数中用位旋转 + XOR 代替 `h * 31 + x`，避免 `OverflowException`。

---

## 已实现（迭代 7 — 代码质量硬化：消除魔鬼数字）

### 背景

> 项目规范要求"如无必要，避免使用魔鬼数字，可定义为含义明确的常量或不可变变量"。
> 迭代 3–5 在快速推进词法器 / 语法器时散落了大量裸 `0x3C` / `0x26` / `0x10FFFF` 等常量，
> 虽然每处都带行内注释，但仍违反规范。本迭代作为一次**集中的、零行为变更的硬化**，
> 在单次提交中把 `parser` 与 `io` 子包内的魔鬼数字全部替换为命名常量。

### 新增：`src/parser/char_codes.cj`（集中的字符码点与数值常量）

- ASCII 语法符号：`CHAR_LT` / `CHAR_GT` / `CHAR_AMP` / `CHAR_HASH` / `CHAR_QUOTE` / `CHAR_APOS` /
  `CHAR_BANG` / `CHAR_QMARK` / `CHAR_SLASH` / `CHAR_MINUS` / `CHAR_DOT` / `CHAR_EQ` / `CHAR_SEMI` /
  `CHAR_COLON` / `CHAR_LBRACKET` / `CHAR_RBRACKET` / `CHAR_UNDERSCORE`。
- ASCII 空白：`CHAR_HT` / `CHAR_LF` / `CHAR_CR` / `CHAR_SPACE`。
- 数位 / 字母区间：`CHAR_DIGIT_0`/`9`、`CHAR_UPPER_A`/`F`/`Z`、`CHAR_LOWER_A`/`F`/`L`/`M`/`N`/`S`/`X`/`Z`。
- XML 1.1 专属换行字符：`NEL_CODEPOINT` (U+0085)、`LINE_SEPARATOR_CODEPOINT` (U+2028)。
- Unicode 界限：`UNICODE_MAX_CODEPOINT` (0x10FFFF)。
- UTF-8 编码尺寸界限：`UTF8_1BYTE_UPPER` / `UTF8_2BYTE_UPPER` / `UTF8_3BYTE_UPPER`（用于 O(1) 计算一个 rune 的字节长度）。
- 字符引用数位换算：`DEC_BASE` / `HEX_BASE` / `HEX_DIGIT_OFFSET`。
- 拼串长度：`XMLNS_COLON_PREFIX_LEN = 6`（`"xmlns:"` 字节数）。

### 改动文件（6 个 `parser` + 2 个 `io`）

- `src/parser/lexer_dispatch.cj`：`0x3C` / `0x26` / `0x5D` / `0x3E` / `0x21` / `0x3F` / `0x2F` 替换为具名常量。
- `src/parser/lexer_markup.cj`：注释 / CDATA / DOCTYPE / PI 边界的 `0x2D` / `0x3E` / `0x5D` / `0x5B` / `0x22` / `0x27` / `0x3F` 替换为具名常量；`Rune(0x3Eu32)` → `Rune(UInt32(CHAR_GT))`。
- `src/parser/lexer_attrs.cj`：open-tag 状态机中 `0x3E` / `0x2F` / `0x3F` / `0x3D` / `0x22` / `0x27` / `0x26` / `0x3C` 全部具名化；AttValue 归一化中 `0x09` / `0x0A` / `0x20` 替换为 `CHAR_HT` / `CHAR_LF` / `CHAR_SPACE`。
- `src/parser/lexer_ref.cj`：字符引用 `#` / `;` / `x` 以及 `A-F`/`a-f`/`0-9` 区间端点、十进制 / 十六进制基数、Unicode 上界 `0x10FFFF` 全部具名化。
- `src/parser/rune_reader.cj`：换行归一化中的 `0x0A` / `0x0D` / `0x85` / `0x2028` 替换为 `CHAR_LF` / `CHAR_CR` / `NEL_CODEPOINT` / `LINE_SEPARATOR_CODEPOINT`。
- `src/parser/xml_parser_qname.cj`：`isAllXmlWhitespace` / `isValidEncodingName` / `startsWithXmlnsColon` / `splitQName` / `runeByteLen` 中所有字面码点替换为 `CHAR_*` / `UTF8_*` 常量。
- `src/io/decoding_source.cj`：把硬编码的 `4096` / BOM 探测 `4` 提升为公开常量 `DecodingSource.READ_BUFFER_SIZE` / `DecodingSource.BOM_PROBE_SIZE`。
- `src/io/source.cj`：`readAll` 内部的 `4096` 提取为包级 `READ_ALL_BUFFER_SIZE` 常量。

### 验证

- 所有修改为**语义无变化**的字面量提取；未引入新行为、新状态或新错误路径。
- 原有的行内注释（`/* '<' */` 之类）不再必要，已一并移除 —— 常量名本身即"自文档"。
- 保持单文件 ≤ 300 行硬约束。
- `encoding/encoding_sink.cj` 中的 BOM 字节数组（如 `[0xEFu8, 0xBBu8, 0xBFu8]`）按规范定义的字节序列，
  所处 `case "utf-8" =>` 分支已通过上下文自文档，故保留原字面形式，不再进一步抽象。

### 下一步（Phase 3c 延后）

Phase 3c（`EntityResolver` 加载外部实体 + `recover=true` 容错路径 + W3C `xmltest` 黄金对比）
仍保留在路线图上，**留给下一迭代**。本迭代专注于项目规范基线，为后续引入更复杂的容错分支
先把代码风格打磨到位。

---

## 已实现（迭代 8 — Phase 4a：只读 DOM + DocumentBuilder）

### 背景

> Phase 3 交付了 `XmlParser: Iterator<SaxEvent>`；下游若要"就地操作一棵树"
> 需要先把事件流物化。本迭代按 `ROADMAP.md` Phase 4 的第一块砖交付**只读
> DOM** 与 `DocumentBuilder`，暂不提供变更 API、`XmlReader`、序列化。
>
> 与 libxml2 的 `tree.c` + `SAX2.c` 对齐但做了两处语言级改进：
>   - 节点根类型 `sealed interface Node` → `match` 分派时编译器强制穷举，
>     彻底淘汰 libxml2 `if node->type == XML_XXX_NODE` 的手写判别；
>   - `Attr` 独立于 `Node`（对齐 W3C DOM Level 2），调用方不会错把属性当
>     成兄弟节点遍历。

### 新增子包：`cangjie_xml.tree`（6 个源文件 + 1 个测试文件）

| 文件 | 行数 | 内容 |
| --- | --- | --- |
| `src/tree/node.cj` | 97 | `sealed interface Node` + `NodeKind` 枚举 |
| `src/tree/attr.cj` | 50 | `Attr`（元素属性，不是 Node；提供 `fromSaxAttribute` 转换） |
| `src/tree/element.cj` | 162 | `Element` + 只读 `children()` / `attributes()` / `findAttribute` / `findChildren` / `directText` / `allText` 遍历 API + 惰性 `ElementChildrenFilter` 迭代器 |
| `src/tree/leaf_nodes.cj` | 161 | `TextNode` / `CdataSection` / `CommentNode` / `PiNode` / `DoctypeNode` |
| `src/tree/document.cj` | 64 | `Document`（`xmlDecl` / `doctype` / `root` / `prolog()` / `epilog()`） |
| `src/tree/document_builder.cj` | 156 | `DocumentBuilder`：消费 `Iterator<SaxEvent>` 构造 `Document` |
| `src/tree/document_builder_test.cj` | 274 | 20 条单元测试 |

### 关键设计决策

1. **不变式：类型系统直接表达"非根节点必然有 `Element` 父"**
   —— `parent()` 统一返回 `?Element`，`Document` 不实现（它没有父）。
   排除了 libxml2 里"父指针指向 xmlDoc" 导致的 downcast 分支。
2. **只读视图而非 `ArrayList` 直接暴露** —— `children()` / `attributes()`
   返回 `Iterator<_>`，防止调用方在构造完成后误作修改。Phase 4b 引入变更
   API 时再同时开放受控的 mutator。
3. **`Element.ns` 保留 `NsContext` 快照** —— 下游做 XPath / C14N / 命名空间
   查询时可直接解析，无需回溯 DOM。对应 libxml2 里挂在 `xmlNode.nsDef` /
   `xmlNode.ns` 的链表，数据结构等价但语义更显式。
4. **`EntityReference` 降级为字面文本** —— `substituteEntities=false` 时
   SAX 流会产生 `EntityReference`；DOM MVP 暂不建模实体引用节点，直接写作
   `&name;` 的 `TextNode`。Phase 4b 引入专用 `EntityRefNode` 后可无缝升级。
5. **`DoctypeNode` 存于 `Document.doctype` 而非 `prolog` 列表**
   —— 与 W3C DOM 对齐（DOCTYPE 属于文档级元数据）；调用方不需要遍历 prolog
   判别 DOCTYPE。

### 新增测试（20 条，全部位于 `src/tree/document_builder_test.cj`）

- 骨架：`testSelfClosingRoot` / `testEmptyRootWithEndTag` / `testNestedElements` / `testSiblingElements`
- 属性：`testAttributes` / `testAttributeEntityExpansion` / `testNamespacedAttribute`
- 文本 / CDATA：`testTextContent` / `testMixedTextAndElements` / `testCdataIndependentNode` / `testAllTextRecursive`
- Prolog / Epilog / Doctype：`testPrologCommentAndPi` / `testEpilogCommentAfterRoot` / `testDoctypeCaptured`
- 查找 / 命名空间：`testFindChildrenByLocalName` / `testFindChildrenByNamespace` / `testElementNsContextPreserved`
- 元数据 / 错误：`testMalformedInputRaises` / `testNodeKindsReportCorrectly` / `testXmlDeclCapturedOrSynthesized`

### 验证

- `cjpm build` 干净，无新的 warning（已修正 `public sealed` 冗余修饰符）。
- `cjpm test` **243 / 243** 全绿（新增 20 + 迭代 7 的 223 全保留）。
- 全部新增文件 ≤ 300 行。

### 下一步（Phase 4b / Phase 3c 仍延后）

- Phase 4b：节点变更 API（`appendChild` / `removeChild` / `replaceChild`）与
  不变量检查（`detached` / 父指针同步 / 跨文档节点拒绝）。
- Phase 4c：`SaxHandler` 推式接口 + `XmlReader` 拉式接口。
- Phase 3c：容错模式 + 外部实体 + W3C `xmltest` 黄金对比（继续延后）。

---

## 已实现（迭代 9 — Phase 5a：基础 DocumentSerializer）

### 背景

> Phase 4a 交付了 `DocumentBuilder: Iterator<SaxEvent> → Document`。
> Phase 5a 把这条链路**闭合**：新增 `DocumentSerializer: Document → String`
> 实现 **parse → serialize → parse** 往返，是 Phase 4/5 的共同出口准则。
>
> 与 libxml2 的 `xmlsave.c` 对齐但做了两处改进：
>   - 非缩进模式下输出字节"贴源"：不自动合成 XML 声明、不注入空白 —— 适合
>     diff-based 的黄金对比；
>   - 缩进模式把"是否可能改变字符数据语义"交给调用方：只含直接 Text / CDATA
>     的叶子元素保持同行，避免缩进污染文本内容。

### 新增子包：`cangjie_xml.save`（3 个源文件 + 1 个测试文件）

| 文件 | 行数 | 内容 |
| --- | --- | --- |
| `src/save/serialize_options.cj` | 65 | `SerializeOptions`：`omitXmlDeclaration` / `indent` / `indentString` / `lineSeparator` / `cdataAsText` / `omitSyntheticXmlDeclaration`；`defaults()` / `pretty()` 预设 |
| `src/save/document_serializer.cj` | 67 | `DocumentSerializer` 主类：字段、公开入口 `write` / `toString` / `elementToString`；通过包级转发桥接 extend 实现 |
| `src/save/document_serializer_nodes.cj` | 246 | `extend DocumentSerializer`：XmlDecl / DOCTYPE / Prolog / Epilog / 元素 / 属性 / 文本 / CDATA / Comment / PI / 缩进全部实现 |
| `src/save/document_serializer_test.cj` | 215 | 24 条单元 + 往返测试 |

### 关键设计决策

1. **"无声明源不被无中生有地写入声明"** —— 为 `XmlDecl` 新增 `isSynthetic: Bool`
   字段；parser 在缺失 `<?xml ...?>` 时将其置 `true`。默认选项
   `omitSyntheticXmlDeclaration = true` 据此识别，避免 `<a/>` 被改写为
   `<?xml version="1.0"?><a/>`。保留了字节等价性的下游能力。
2. **主类 + extend 桥接模式** —— Cangjie 主类体不能直接调用 extend 成员，
   沿用 `XmlParser` 同款：主类只放字段 + 公开入口 + 包级 `serializeDocument` /
   `serializeElementOnly` 转发函数；所有输出逻辑集中在 extend 文件。
3. **缩进采用"叶子文本保护"策略** —— `isLeafTextElement` 判定直接子节点是否
   全部为 Text / CDATA；若是则保持同行输出，避免缩进空白修改字符数据。
   与 libxml2 `xmlSaveFormatFile` 的默认行为一致。
4. **CDATA 双模式** —— 默认保留为 `<![CDATA[...]]>` 独立节点；
   `cdataAsText = true` 时降级为转义文本，字节更短但丢失 CDATA 语义。
5. **复用现有工具** —— 文本 / 属性转义直接调 `core.escapeXml`；QName 输出
   调 `QName.lexical()`；零额外依赖。

### 新增测试（24 条，`src/save/document_serializer_test.cj`）

基础（8）：`testSelfClosingEmpty` / `testPairedWithText` / `testNestedDefaultNoIndent` /
`testAttributesEscapedAndQuoted` / `testNamespaceDeclarationsPreserved` /
`testTextContentEscaped` / `testCdataPreservedByDefault` / `testCdataAsTextLowers`

Prolog / Epilog / 声明 / DOCTYPE（6）：`testCommentAndPiInProlog` /
`testCommentInEpilog` / `testRealXmlDeclPreserved` /
`testSyntheticXmlDeclOmittedByDefault` / `testOmitXmlDeclarationForces` /
`testDoctypeEmitted` / `testStandaloneFlags`

缩进 + 片段（3）：`testPrettyIndent` / `testPrettyCustomIndentString` /
`testElementToStringFragment`

端到端 round-trip（6）：`testRoundTripSimple` / `testRoundTripAttributesAndNs` /
`testRoundTripMixedContent` / `testRoundTripCdata` /
`testRoundTripEntitiesInAttribute` / `testRoundTripPrettyPreservesStructure`

### 顺带的基础设施改进

- `XmlDecl` 新增 `isSynthetic: Bool`（默认 `false`，非破坏性）。
- `XmlParser.handleStartDocument` / `DocumentBuilder.finalize()` 在合成 XmlDecl
  时置 `isSynthetic: true`。
- 既有 104 个 parser 测试 + 20 个 tree 测试不受影响。

### 验证

- `cjpm build` 干净。
- `cjpm test` **267 / 267** 全绿（243 旧 + 24 新）。
- 全部新增文件 ≤ 300 行。

### 下一步（候选）

- Phase 5b：`XmlWriter` 推式接口（`startElement` / `writeAttribute` / `endElement`
  栈机）+ `IoSink` 整合 + 编码转换。
- Phase 4b：DOM 变更 API（`appendChild` / `removeChild` / `replaceChild` +
  不变量检查）。
- Phase 4c：`SaxHandler` / `XmlReader`。
- Phase 3c：容错 + 外部实体 + W3C `xmltest` 黄金对比（继续延后）。

---

## 已实现（迭代 10 — Phase 5b：推式 `XmlWriter`）

### 背景

> Phase 5a 交付了"拉"式输出（`DocumentSerializer`：从 DOM 整体拍出字符串）。
> Phase 5b 补上"推"式输出：**调用方按顺序 `startElement` / `writeAttribute` /
> `writeText` / `endElement`，直接写到 `IoSink`**。
>
> 与 libxml2 `xmlwriter.c` 对齐但做了一个关键改进：**所有状态违规立即抛异常并
> 置 `faulted`**，之后任何写入都拒绝。libxml2 把很多错误状态静默化（写入失败
> 却 API 继续返回 0），CangjieXML 明确禁止继续写入被污染的流，防止生成不良构
> XML 被下游误信任。

### 新增子包：`cangjie_xml.writer`（4 个源文件 + 1 个测试文件，均 ≤ 300 行）

| 文件 | 行数 | 内容 |
| --- | --- | --- |
| `src/writer/writer_options.cj` | 44 | `WriterOptions`：`omitXmlDeclaration` / `indent` / `indentString` / `lineSeparator`；`defaults()` / `pretty()` 预设 |
| `src/writer/xml_writer.cj` | 230 | `XmlWriter` 主类：字段 / 公开入口 / `WriterState` 枚举 / `ElementFrame` 栈帧 / `Standalone3` 三态枚举；包级转发桥接 |
| `src/writer/element_stack.cj` | 68 | `ElementStack`：push/pop/top + `markNonLeafChild` / `markAnyChild` 辅助 |
| `src/writer/xml_writer_ops.cj` | 289 | `extend XmlWriter`：状态机 + 全部写入动作 + 缩进 + 错误处理 |
| `src/writer/xml_writer_test.cj` | 292 | 30 条单元测试 |

### 公开 API

**构造**
```cangjie
XmlWriter(sink: IoSink, opts!: WriterOptions = WriterOptions())
```

**prolog 阶段**
- `writeXmlDeclaration(version, encoding, standalone)` — 只能在首次写入前，
  或 `WriterOptions.omitXmlDeclaration=true` 时被显式拒绝；
- `writeDoctype(name)` — 在 prolog 阶段允许。

**元素**
- `startElement(QName | String)` — 入栈；进入 `InElementOpen` 状态等待属性；
- `writeAttribute(QName | String, value)` — 必须紧跟 `startElement`，
  否则抛错并置 `Faulted`；
- `writeNamespace(prefix: ?String, uri)` — 便捷属性（`xmlns` / `xmlns:p`）；
- `endElement()` — 空元素自闭合为 `<a/>`；非空元素写 `</a>`，关闭栈顶。

**内容**
- `writeText(data)` — 自动转义 `&`/`<`/`>`；自动关闭 pending start-tag；
- `writeCdata(data)` — 包裹 `<![CDATA[...]]>`；禁止嵌入 `]]>`；
- `writeComment(data)` — 禁止 `--`；prolog / content / epilog 皆可；
- `writePi(target, data)` — 校验非空 + 拒绝保留名 `xml`（任意大小写）+ 禁止 `?>`；
- `writeRawBytes(bytes)` — 直通 sink，调用方自担良构性。

**收尾**
- `close()` — 要求栈已空；flush sink；设 `Closed`；**不关闭 sink**（所有权
  保留在调用方，便于 `MemorySink.toBytes()`）；对已 Closed / Faulted 的实例
  幂等。

### 关键设计决策

1. **显式状态机 `WriterState`** — `Start / Prolog / InElementOpen /
   InElementContent / Epilog / Closed / Faulted`。每个方法入口 `requireAlive()`
   拒绝 Closed / Faulted，所有违规走 `fail(msg)` 抛 `XmlException(XmlError.Other)`
   并设 `Faulted`。
2. **`Standalone3` 本地化** — 避免 `writer` 反向依赖 `parser`。与
   `parser.Standalone` 语义同构，未来若需互转可加一个 Phase 5c 的适配函数。
3. **`ElementFrame` 携带 `leafTextOnly` + `hasAnyChild`** —
   - `leafTextOnly` 决定缩进模式下 `endElement` 是否换行：纯文本元素保持同行；
   - `hasAnyChild` 保留未来用于"空元素是否允许自闭合"的策略（当前未用，空元素
     始终自闭合）。
4. **良构性最小断言** — writer 不做全量 XML 校验（那是 parser 的活），但对
   几种"写出来就必然不良构"的 case 主动拦截：`]]>` in CDATA、`--` in comment、
   `?>` in PI data、PI target = `xml`。
5. **主类 + extend 桥接** — 沿用 parser / save 子包同款模式，绕开 "Cangjie
   主类体不能调用自身 extend 成员"限制。

### 新增测试（30 条）

- 基础（10）：自闭合空元素 / 属性 / 属性转义 / 文本转义 / 嵌套 / 混合内容 /
  CDATA / Comment+PI / 命名空间 / QName 重载
- Prolog / Epilog（5）：XML 声明 / standalone / DOCTYPE / prolog 注释 PI /
  epilog 注释
- 缩进（2）：pretty 结构 / 叶子文本保持同行
- writeRawBytes（1）：直通
- 状态机违规（10）：XML 声明错位 / omit 拒绝 / endElement 无 start /
  属性错位 / 多根 / 未闭合 close / close 后写 / CDATA 终止序列 /
  comment 双短横线 / PI 保留名
- 其它（2）：`depth()` / close 幂等

### 基础设施改进

无。写入器完全基于现有 `core.escapeXml` / `QName.lexical()` / `IoSink`
接口，零破坏性变更。

### 验证

- `cjpm build` 干净；
- `cjpm test` **297 / 297** 全绿（267 旧 + 30 新）；
- 所有新文件 ≤ 300 行；
- 主类函数圈复杂度 ≤ 6。

### 下一步（候选）

- Phase 4b：DOM 变更 API（`appendChild` / `removeChild` / `replaceChild` +
  不变量检查）；
- Phase 4c：`SaxHandler` / `XmlReader`；
- Phase 5c：`writer.NamespaceScope`（写时作用域跟踪，与 save / 未来 C14N 共用）；
- Phase 3c：容错 + 外部实体 + W3C `xmltest` 黄金对比。

---

## 已实现（迭代 11 — Phase 4c：拉式 `XmlReader`）

### 背景

> Phase 3b 提供了 `XmlParser: Iterator<SaxEvent>`（推 / 迭代器模式）。
> Phase 4a 提供了 `DocumentBuilder: Iterator<SaxEvent> → Document`（物化）。
> 本迭代补上 **"拉式游标"**：.NET `XmlReader` / libxml2 `xmlTextReader` 风格
> —— 调用方 `read()` 前进一步，用字段查询当前节点。与事件迭代器相比，
> `XmlReader` 更贴合"按需深入子树 / 跳过子树"的场景（如 RSS/Atom 聚合、
> 配置文件定点提取），也是"零材料化流式解析"的主接口。

### 新增子包：`cangjie_xml.reader`（3 个源文件 + 1 个测试文件，均 ≤ 300 行）

| 文件 | 行数 | 内容 |
| --- | --- | --- |
| `src/reader/reader_types.cj` | 110 | `ReaderNodeType`（13 态）+ `ReaderState`（5 态），`Equatable`/`ToString` |
| `src/reader/xml_reader.cj` | 230 | `XmlReader` 主类：字段、静态构造、状态查询、名字 / 属性游标 API、包级桥接 |
| `src/reader/xml_reader_ops.cj` | 240 | `extend XmlReader`：`runRead` / `runSkip` + 深度调整 + 名字 / 值派生 + 异常拦截 |
| `src/reader/xml_reader_test.cj` | 270 | 25 条单元测试 |

### 公开 API

```cangjie
// 构造
XmlReader.fromString(s, opts)
XmlReader.fromParser(existingParser)

// 前进
read(): Bool                // true = 还有节点；false = EOF 或错误
skip(): Bool                // 跳过当前元素的子树，停在配对 EndElement

// 状态
readerState(): ReaderState
isClosed(): Bool
isEof(): Bool
depth(): Int64              // 当前嵌套深度；根元素 = 0
isEmptyElement(): Bool      // 当前 Element 是否是 <a/> 形态
nodeType(): ReaderNodeType
position(): Position

// 名字 / 值
localName() / prefix() / namespaceUri() / name()
value() / hasValue()

// 属性游标（不消费事件，只切换内部 cursor）
hasAttributes(): Bool
attributeCount(): Int64
moveToAttribute(i)
moveToAttribute(localName, uri?)
moveToFirstAttribute() / moveToNextAttribute() / moveToElement()

// 生命周期
close()
```

### 关键设计决策

1. **单事件预读** — 内部只保留 `peeked: ?SaxEvent` 一个 slot，用于两件事：
   (a) **空元素检测**：`StartElement` 后窥视一步，若下一事件是 `EndElement`
   则 `emptyElement = true`，后续 `read()` 会静默消费这个配对 EndElement；
   (b) **延迟结算深度**：对 `EndElement` 与空 `Element` 的深度在"下一次 read"
   开始时处理，保证当前节点报告的 `depth` 正确。不做任意回放，内存恒定。
2. **属性是"虚拟节点"** — `moveToAttribute` 只切换 `attrCursor: Int64`
   字段，不消费 SaxEvent；这期间 `nodeType` 暂时返回 `Attribute`，
   `localName` / `value` / `namespaceUri` 从宿主 `StartElement` 的
   `Array<Attribute>` 中查出。`read()` 会重置 `attrCursor = -1`。
3. **`Whitespace` 自动识别** — Parser 产出的 `Characters` 若内容全为
   XML 1.0 §2.3 定义的空白（`#x20 | #x9 | #xD | #xA`），`nodeType`
   报告为 `Whitespace` 而不是 `Text`。这是 `XmlReader` 的常规行为：
   便于下游按空白跳过（混合内容解析场景）。
4. **错误处理** — 两层：(a) 若 parser 抛 `XmlException`（如非良构）
   在 `pullEvent` 包一层 try-catch，把 `state` 置 `Error` 再上抛；
   (b) 若 parser 以 `ParseError` 事件透传（recover 模式，本迭代尚未开启），
   入 `runRead` 立即抛并置 `Error`。`Error`/`Closed`/`EndOfFile`
   之后的 `read()` 返回 false 且不重入 parser。
5. **不实现 `readInnerXml` / `readOuterXml`** — 二者需要和序列化器联动
   （从当前光标位置重新序列化子树）。留待下一迭代（Phase 4c+）补上，
   可复用 `save.DocumentSerializer`。
6. **主类 + extend 桥接** — 沿用 parser / save / writer 的约定。

### 新增测试（25 条）

- 基础遍历（9）：初始状态 / 自闭合 / `<a>text</a>` / 三层嵌套深度 / 混合内容 /
  CDATA / Comment / PI / Whitespace-vs-Text
- 属性游标（4）：index 顺序 / 按名字 / 越界 / name+prefix+uri 派生
- skip（3）：子树跳过 / 空元素等价 `read()` / 非 Element 上等价 `read()`
- 生命周期（2）：close / EOF 重复调用
- 错误（1）：非良构触发 `XmlException` + state=Error
- 其它（6）：fromParser / XmlDeclaration / Doctype / position / 属性游标在
  read 时自动复位 / 实体引用自动展开

### 验证

- `cjpm build` 干净（无错、仅历史 unused-function 警告）；
- `cjpm test` **322 / 322** 全绿（297 旧 + 25 新）；
- 所有新文件 ≤ 300 行；
- 主类 / extend 无字段改写冲突。

### 下一步（候选）

- Phase 4b：DOM 变更 API（`appendChild` / `removeChild` / `replaceChild` +
  `detached` 不变量）；
- Phase 4d：`SaxHandler` / `DefaultSaxHandler`（推式回调接口，配合 `XmlReader`
  或 `DocumentBuilder` 双向转接）；
- Phase 4c+：`XmlReader.readInnerXml` / `readOuterXml` + `readSubtree`
  （复用 `DocumentSerializer`）；
- Phase 5c：共享 NamespaceScope 跟踪器（C14N 预埋）；
- Phase 3c：容错模式 + 外部实体 + W3C xmltest 黄金对比。
