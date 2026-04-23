# CangjieXML

> **纯仓颉语言实现的 XML 工具链 —— libxml2 的现代化复刻。**

CangjieXML 以 [libxml2 v2.15.3](./.libxml2-2.15.3) 为功能对标，用仓颉（Cangjie）编程语言重新设计并实现一套 **类型安全、内存安全、线程友好、可组合** 的 XML 工具链。仅依赖 `std.*` 与必要的 `stdx.*`，**不使用互操作、其他编程语言及三方库**。

- 设计依据：[`DESIGN.md`](./DESIGN.md) —— 做什么 / 为什么
- 渐进计划：[`ROADMAP.md`](./ROADMAP.md) —— 何时做 / 如何分阶段
- 当前进度：[`progress.md`](./progress.md) —— 相对 libxml2 全量功能的实现情况

---

## 构建与测试

前置：[仓颉 SDK 1.0.5](https://github.com/SunriseSummer/CangjieSDK/releases/download/1.0.5/cangjie-sdk-linux-x64-1.0.5.tar.gz)。安装并 `source <sdk>/envsetup.sh` 之后：

```bash
# 编译全部包
cjpm build

# 运行全部单元测试
cjpm test

# 代码格式化（配合 cangjie-format.toml）
cjfmt -d src/ -c cangjie-format.toml
```

## 项目布局

```
CangjieXML/
├── cjpm.toml              # 顶层模块清单
├── cangjie-format.toml    # 格式化配置
├── DESIGN.md / ROADMAP.md # 设计与计划
├── progress.md            # 相对 libxml2 的进度清单
└── src/
    ├── cangjie_xml.cj     # 顶层门面（后续汇总 public import）
    ├── core/              # ✅ Phase 1 基础设施模块
    ├── encoding/          # ✅ Phase 2 前半：字符编解码模块
    └── io/                # ✅ Phase 2 后半：I/O 抽象与装饰器
```

> 项目采用单 `cjpm` 模块 + 子目录子包的布局（每个 `src/<name>/` 对应一个 `cangjie_xml.<name>` 子包），相比 `DESIGN.md` 最初构想的"多 workspace"方案更贴合 `cjpm 1.0.5` 的实际能力。后续阶段的各模块（`encoding`、`parser`、`tree` …）将以相同模式陆续引入 `src/` 下。

---

## 已实现模块

### `core` —— 基础设施（Phase 1）

对应 libxml2 的 `chvalid.c` / `xmlstring.c` / `buf.c` / `dict.c` / `error.c` / `uri.c`。由下列源文件构成：

| 文件 | 对应 libxml2 | 核心 API |
| --- | --- | --- |
| `char_valid.cj` | `chvalid.c` | `isXmlChar` / `isNameStartChar` / `isNameChar` / `isXmlWhitespace` / `isPubidChar` / `isValidName` / `isValidNcName` / `isValidXmlString` / `isXml11RestrictedChar` |
| `buffer.cj` | `buf.c` | `GrowableBuffer`、`BoundedBuffer`（带上限的防御性缓冲） |
| `string_util.cj` | `xmlstring.c` | `bytesToString` / `escapeXml` / `normalizeWhitespace` / `normalizeNewlines` |
| `name_table.cj` | `dict.c`、`hash.c` | `NameTable`（非并发 intern 池）、`ConcurrentNameTable`（基于 `ConcurrentHashMap`） |
| `qname.cj` | —（libxml2 中散落于多处） | 不可变 `QName`，比较仅看 `(localName, uri)`，与前缀无关 |
| `error.cj` | `error.c` | `Position`、`Severity`、`XmlError`（分支枚举）、`XmlException`、`ErrorCollector`、`ListErrorCollector`、`SilentErrorCollector` |
| `uri.cj` | `uri.c` | `Uri`（严格 RFC 3986 解析 / 归一化 / 基于 base 的相对参考解析） |

#### 使用示例

```cangjie
import cangjie_xml.core.*

main() {
    // 1. 校验 XML 名字
    println(isValidName("xs:element")) // true

    // 2. 字符转义
    println(escapeXml("a & b < c", forAttribute: false)) // a &amp; b &lt; c
    println(escapeXml("say \"hi\"", forAttribute: true)) // say &quot;hi&quot;

    // 3. URI 解析与相对参考解析（RFC 3986 §5.4 黄金示例）
    let base = Uri.parse("http://a/b/c/d;p?q")
    let ref = Uri.parse("../../g")
    println(ref.resolve(base)) // http://a/g

    // 4. 命名空间限定名
    let q = QName("elem", prefix: Some("p"), uri: Some("urn:demo"))
    println(q.expanded()) // {urn:demo}elem

    // 5. 诊断收集
    let collector = ListErrorCollector()
    collector.report(Severity.Error, XmlError.UriError("bad"))
    println(collector.size()) // 1
}
```

#### 覆盖的 libxml2 等价点

- XML 1.0 / 1.1 字符类与 `NameStartChar` / `NameChar` / `PubidChar` 与 W3C 规范逐区间对齐；
- `Uri.resolve` 通过 RFC 3986 §5.4.1（正常示例 23 条）与 §5.4.2（异常示例 8 条）单元测试；
- `escapeXml` 在"内容"与"属性值"两种模式下输出与 libxml2 `xmlEncodeSpecialChars` / `xmlEncodeEntitiesReentrant` 语义对齐；
- `normalizeNewlines` 覆盖 XML 1.0 行尾归一化与 XML 1.1 NEL/LS 额外归一化；
- `NameTable` 对应 `xmlDict`，提供 intern 语义且不存在 C 版的引用计数陷阱。

---

### `encoding` —— 字符编解码（Phase 2 前半）

对应 libxml2 的 `encoding.c`。提供 BOM 探测、流式解码器、一次性编码器以及名字归一化的编码注册表。

| 文件 | 提供 |
| --- | --- |
| `status.cj` | `DecodeStatus` / `DecodeResult` / `EncodeStatus` / `EncodeResult` / `BomKind` / `encodingError` |
| `bom.cj` | `detectBom`（严格 BOM 签名，UTF-32 优先于 UTF-16）/ `heuristicDetect`（W3C §F 附录 `<?xml` 对齐模式） |
| `decoder.cj` | `abstract class Decoder`（流式状态保留，跨分片不丢半截序列） |
| `encoder.cj` | `abstract class Encoder` |
| `utf8.cj` | `Utf8Decoder`（RFC 3629 拒绝超长 / 代理 / > U+10FFFF）+ `Utf8Encoder` |
| `utf16.cj` | `Utf16Decoder` / `Utf16Encoder` 的 LE + BE 两种构造器，严格代理对 + 可选 BOM 输出 |
| `utf32.cj` | `Utf32Decoder` LE + BE，拒绝代理与越界码点 |
| `single_byte.cj` | `SingleByteDecoder` / `SingleByteEncoder` 框架 + US-ASCII、ISO-8859-1/-2/-3/-4/-5/-9/-15 映射表 |
| `registry.cj` | `EncodingRegistry`：按名字归一化 + 别名查找、`defaultRegistry()` 预注册全部内置编码 |

#### 使用示例

```cangjie
import cangjie_xml.encoding.*

main() {
    // 1. BOM 探测（优先级正确：UTF-32 LE 不会被误判为 UTF-16 LE）
    let head: Array<Byte> = [0xFFu8, 0xFEu8, 0x00u8, 0x00u8, 0x41u8]
    println(detectBom(head))                      // Some(utf-32le)

    // 2. 流式 UTF-8 解码（跨分片 state 自动保留）
    let d = Utf8Decoder()
    let r1 = d.decode([0xE4u8, 0xB8u8], 0, 2, false)
    println(r1.status)                            // NeedMoreInput
    let r2 = d.decode([0xADu8], 0, 1, true)
    println(r1.text + r2.text)                    // 中

    // 3. UTF-16 BE 往返
    let be = Utf16Encoder.bigEndian(emitBom: false)
    let bd = Utf16Decoder.bigEndian()
    println(bd.decodeAll(be.encodeAll("😀")))      // 😀

    // 4. 通过注册表按名字拿解码器（不区分大小写 / 连字符 / 下划线）
    let reg = EncodingRegistry.defaultRegistry()
    let latin = reg.newDecoder("ISO_8859-1").getOrThrow()
    println(latin.decodeAll([0xE9u8]))            // é

    // 5. 不可表达的码点 → 结构化诊断
    match (reg.newEncoder("us-ascii").getOrThrow().encode("Hi 中")) {
        case Unmappable(i, cp) => println("unmappable @${i} U+${cp}")
        case Success            => ()
    }
}
```

#### 覆盖的 libxml2 等价点

- BOM 探测覆盖 libxml2 `xmlDetectCharEncoding` 的所有前 4 字节签名（含 UTF-32 BE/LE）；
- UTF-8 解码严格贯彻 RFC 3629：拒绝 0xC0/0xC1 前缀、overlong、> U+10FFFF、U+D800..DFFF 代理；
- UTF-16 解码严格校验代理对配对，孤立 / 悬挂 / 双高位代理均给出 `InvalidBytes(offset)` 诊断；
- 单字节编码差异表对照 Unicode.org 官方 `8859-x.TXT`，ISO-8859-3 保留"未定义"位并解码时报错；
- `EncodingRegistry.normalize` 行为与 libxml2 `xmlParseCharEncoding` 的名字比较等价（大小写 / 连字符 / 下划线不敏感）。

---

### `io` —— I/O 抽象与装饰器（Phase 2 后半）

对应 libxml2 的 `xmlIO.c`（不含 nano-HTTP / FTP —— 按 `DESIGN.md` 非目标，网络资源通过 `StreamSource` 包裹 `stdx.net` 流接入）。

| 文件 | 提供 |
| --- | --- |
| `source.cj` | `interface IoSource` + `MemorySource` / `StringSource` / `StreamSource` / `FileSource` + `readAll` |
| `sink.cj` | `interface IoSink` + `MemorySink` / `StreamSink` / `FileSink` |
| `buffered_sink.cj` | `BufferedSink` 装饰器（小写聚合、大写旁路、`close` 自动 flush） |
| `indenting_sink.cj` | `IndentingSink` 装饰器（命令式 `increase/decrease/writeIndent`，可配置 `indentUnit` / `newline`） |
| `encoding_sink.cj` | `EncodingSink` 装饰器（UTF-8 → 任意编码；复用 `encoding.Encoder`；支持流式分片与 BOM） |
| `decoding_source.cj` | `DecodingSource`（字节 `IoSource` → 字符串；BOM / hint / 显式优先级协商、自动跳 BOM） |

#### 使用示例

```cangjie
import cangjie_xml.io.*
import cangjie_xml.encoding.*

main() {
    // 1. 把 String 当输入源，读出字节
    let src = StringSource("Hello 中", baseUri: Some("mem://demo"))
    println(readAll(src).size)                // 10（6 ASCII + 中 = 3 字节 + 空格 = 10）

    // 2. BufferedSink + IndentingSink 组合，输出到内存
    let mem = MemorySink()
    let indent = IndentingSink(BufferedSink(mem, capacity: 64), indentUnit: "  ")
    indent.write("<root>".toArray())
    indent.increaseIndent()
    indent.writeIndent()
    indent.write("<child/>".toArray())
    indent.decreaseIndent()
    indent.writeIndent()
    indent.write("</root>".toArray())
    indent.close()                            // 级联 flush + close
    println(String.fromUtf8(mem.toBytes()))   // <root>\n  <child/>\n</root>

    // 3. 用 EncodingSink 把 UTF-8 源字节转成 UTF-16 BE + BOM
    let out = MemorySink()
    let enc = EncodingSink(out, Utf16Encoder.bigEndian(emitBom: false), writeBom: true)
    enc.write("A".toArray())
    enc.close()                               // → [FE FF 00 41]

    // 4. DecodingSource 自动识别编码，剥离 BOM
    let bytes = [0xFEu8, 0xFFu8, 0x00u8, 0x41u8, 0x00u8, 0x42u8]    // UTF-16 BE BOM + "AB"
    let ds = DecodingSource(MemorySource(bytes))
    println(ds.detectedEncoding)              // utf-16be
    println(ds.readAllAsString())             // AB
}
```

#### 覆盖的 libxml2 等价点

- `IoSource` / `IoSink` 对齐 `xmlParserInputBuffer` / `xmlOutputBuffer` 的核心回调（`read` / `write` / `close`），但摒弃 `void*` 上下文；
- `BufferedSink` 等价于 libxml2 output buffer 的内部缓冲；
- `IndentingSink` 提供 libxml2 `xmlSaveFormatFile*` 的缩进能力，但把"何时换行"的语义责任留给上层 writer；
- `EncodingSink` 对齐 `xmlCharEncOutFunc` 的转码桥；
- `DecodingSource` 对齐 libxml2 解析器启动时的"检测编码 → 切换解码器 → 跳 BOM"流程，优先级与 W3C XML §4.3.3 + libxml2 实现一致。

---

## 仍未实现

见 [`progress.md`](./progress.md)。按 `ROADMAP.md` 顺序，下一迭代进入 **Phase 3 —— `parser` 包（词法 + SAX 事件流）**，会把本迭代的 `DecodingSource` 作为词法器的字符输入。
