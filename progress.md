# CangjieXML 开发进度

> 相对 [libxml2 v2.15.3](./.libxml2-2.15.3) 全量功能的实现情况。最新更新：迭代 1 结束（Phase 1 `core` 模块）。

---

## 总览

| Phase | 模块 | 对应 libxml2 | 状态 |
| --- | --- | --- | --- |
| 0 | 项目骨架 | — | ✅ 已完成 |
| 1 | `core` 基础设施 | `chvalid`、`xmlstring`、`buf`、`dict`、`hash`、`error`、`uri` | ✅ 已完成 |
| 2 | `encoding` + `io` | `encoding.c`、`xmlIO.c` | ⬜ 未开始 |
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

**粗略完成度**：核心功能 ≈ 5%（仅覆盖 Phase 1 的基础设施；不含解析器 / DOM / 验证器 / 序列化器 / 工具链）。

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

## 未实现（Phase 2 及之后）

按 `ROADMAP.md` 顺序依次推进：

- Phase 2 `encoding` / `io`：BOM 探测、UTF-8 / 16 / 32、ISO-8859-* 解码；`IoSource` / `IoSink` / 装饰器
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
