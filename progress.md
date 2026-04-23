# CangjieXML 开发进度

> 相对 [libxml2 v2.15.3](./.libxml2-2.15.3) 全量功能的实现情况。最新更新：迭代 3 结束（Phase 2 完成 —— `encoding` + `io`）。

---

## 总览

| Phase | 模块 | 对应 libxml2 | 状态 |
| --- | --- | --- | --- |
| 0 | 项目骨架 | — | ✅ 已完成 |
| 1 | `core` 基础设施 | `chvalid`、`xmlstring`、`buf`、`dict`、`hash`、`error`、`uri` | ✅ 已完成 |
| 2 | `encoding` + `io` | `encoding.c`、`xmlIO.c` | ✅ 已完成 |
| 3 | `parser` 词法 + 事件流 | `parser.c`、`parserInternals.c` | ⬜ 未开始 |
| 4 | `tree` + `sax` + `reader` | `tree.c`、`SAX2.c`、`xmlreader.c` | ⬜ 未开始 |
| 5 | `writer` + `save` | `xmlwriter.c`、`xmlsave.c` | ⬜ 未开始 |
| 6 | `xpath` | `xpath.c` | ⬜ 未开始 |
| 7 | `regexp` + `pattern` + `dtd` | `valid.c`、`xmlregexp.c`、`pattern.c` | ⬜ 未开始 |
| 8 | `schema` | `xmlschemas.c`、`xmlschemastypes.c` | ⬜ 未开始 |
| 9 | `relaxng` + `schematron` | `relaxng.c`、`schematron.c` | ⬜ 未开始 |
| 10 | `catalog` + `xinclude` + `c14n` + `xpointer` | `catalog.c`、`xinclude.c`、`c14n.c`、`xpointer.c` | ⬜ 未开始 |
| 11 | `html` | `HTMLparser.c`、`HTMLtree.c` | ⬜ 未开始 |
| 12 | 工具链与发布 | `xmllint.c`、`xmlcatalog.c` | ⬜ 未开始 |
| 13 | 硬化与优化 | `runtest.c`、`fuzz/` | ⬜ 未开始 |

**粗略完成度**：核心功能 ≈ 13%（Phase 1 基础设施 + Phase 2 的字符编解码与 I/O 抽象；不含解析器 / DOM / 验证器 / 序列化器 / 工具链）。

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

- ✅ ~~Phase 2 `io`：`IoSource` / `IoSink` / `BufferedSink` / `IndentingSink` / `EncodingSink`~~（本迭代完成，详见上文）
- Phase 3 `parser`：`ByteReader` / `RuneReader` / `Lexer` / `XmlParser` → `Iterator<SaxEvent>`
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

## 与 `DESIGN.md` / `ROADMAP.md` 的对齐调整

本迭代为适配 `cjpm 1.0.5` 的实际能力，对设计做了以下小幅调整（均以"提升产品质量与可行性"为目标导向）：

1. **包布局**：`DESIGN.md §4` 原方案是 `cjpm` workspace + `packages/<name>/`；`cjpm 1.0.5` 未提供 workspace 子命令，改为 **单模块 + `src/<name>/` 子包** 布局，各包导入路径变为 `cangjie_xml.<name>.*`。语义等价，后续阶段沿用。
2. **`Byte` 构造**：`Byte` 作为 `UInt8` 的类型别名在当前 SDK 下不能作为构造函数调用，内部统一写作 `UInt8(...)`。公共 API 签名仍使用 `Byte` 类型别名。
3. **哈希混合**：Cangjie 的 `*` 默认做溢出检查，散列函数中用位旋转 + XOR 代替 `h * 31 + x`，避免 `OverflowException`。
