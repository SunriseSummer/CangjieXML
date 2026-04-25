# cangjie_xml 性能调优中观察到的仓颉编译器 / 运行时 / 标准库低效问题

> **背景**：`cangjie_xml` 在两轮针对性优化后（详见 `perf/report.md` "已落地的优化"
> 11 项），相对 tinyxml2 的倍率从 30~70× 收敛到 6~35×；继续往下挖掘后，发现
> **剩余差距并非来自库自身的算法选择，而是落在仓颉通用基础设施上**——同一类
> 问题会同时拖慢 JSON / TOML / 协议解析 / 字符串模板渲染等任何字符密集型库。
>
> 本文档把这些观察按"症状 → 复现路径 → 已尝试 workaround → 影响估算 → 改进
> 建议"五段式整理，旨在反馈给 Cangjie SDK 团队；与 `cangjie_xml` 库本身的
> bug 无关。
>
> **环境**：仓颉 SDK 1.0.5（cjnative，`x86_64-unknown-linux-gnu`），
> 仓颉 STDX 1.0.5.1。基准对照对象：tinyxml2 11.0.0（C++ -O2）、
> Python 3 `xml.etree`（CPython 3.12）。

---

## 优先级速览

| # | 模块 | 主题 | 量化影响（XML 库视角） | 优先级 |
|---|---|---|---|---|
| P1-1 | runtime | `Rune` 等价于 4 字节 UTF-32，无紧凑 UTF-8 视图 | parse 内存峰值 ~5×；5 MB ASCII 输入需 4 GB heap 才不 OOM | **P1** |
| P1-2 | compiler | 闭包参数 `(T) -> R` 触发堆分配，无 `@inline` / value-closure | hot loop 上百万次闭包分配，GC 压力主源 | **P1** |
| P2-1 | std.collection | `Iterable` / `Iterator` 接口虚分发 + `Option<T>` 装箱 | writer 在 50K 元素 × N 属性场景每次都分配迭代器 | P2 |
| P2-2 | std.core | `String.runes()` 无零开销 `forEachByte` 替代品 | escape / whitespace 检测被迫绕字节级实现 | P2 |
| P2-3 | std.core | `StringBuilder` 缺公开容量预分配 API | 长串构造 ~19 次扩容副本拷贝 | P2 |
| P2-4 | std.collection | `HashMap<String, V>` 哈希对短键也走全字节扫描 | parser 属性表插入耗时占比 ~8% | P2 |
| P3-1 | std.core | `String → Array<Byte>` 与 `StringBuilder → Array<Byte>` 多一次 UTF-8 编码 | `writeXmlToBytes` 路径多一次全量字节拷贝 | P3 |
| P3-2 | compiler/runtime | 缺 SIMD intrinsic / `strchr` 等价物 | 字节扫描"特殊字符"只能逐字节 if，无法接近 C 量级 | P3 |

---

## P1-1：`Rune` 等价于 4 字节 UTF-32，无紧凑 UTF-8 视图

### 症状

- `String` 文档明示内部 UTF-8 存储，但任何字符级操作（`runes()`、`Rune` 比较、
  `String(Array<Rune>)` 等）都隐含一次 UTF-8 ↔ UTF-32 解码 / 编码。
- 把"按字符扫描的 Parser"用 `Array<Rune>` 实现，5 MB ASCII 输入需要 ~20 MB 的
  Rune 数组（每码点 4 字节），叠加 `ArrayList` 倍增扩容副本一度 ~40 MB。
- 默认 heap 256 MB 时，`run.py` 的 5 MB `catalog_large.xml` 直接 OOM；当前
  `perf/run.py` 通过 `cjHeapSize=4GB` 规避（参见
  `perf/run.py` `_ensure_cangjie_heap()`）。

### 复现路径

```cangjie
// src/parser/source_cursor.cj — 非 ASCII fallback 仍需走这条路径
init(input: String, acceptBom: Bool) {
    let tmp = ArrayList<Rune>(input.size)  // 已预估容量
    for (r in input.runes()) {             // 每次迭代解码一个码点
        tmp.add(r)
    }
    this.runes = tmp.toArray()             // 又一次拷贝
}
```

`for r in input.runes()` 实际驱动了 (a) UTF-8 解码、(b) `Iterator<Rune>` 的
`next(): ?Rune` 调用 + Option 装箱、(c) `ArrayList.add` 的容量检查与赋值。
对每个码点都付一次。

### 已尝试 workaround

- `ArrayList<Rune>(input.size)` 预估容量，省 19 次 doubling 副本拷贝（见
  `source_cursor.cj` init）。**收益有限**，根本原因——4 字节宽度本身——无解。
- `SourceCursor` 增加 ASCII-only 快路径：先按字节确认输入全 ASCII，再用
  `Array<Rune>(input.size, { i => Rune(UInt32(input[i])) })` 直接构造 rune 数组，
  跳过 `String.runes()` 迭代器与 `ArrayList.toArray()` 二次拷贝。该方案让 perf
  9 个 ASCII fixture 的 parse / roundtrip 继续获得 15%~35% 改善，但对真实
  Unicode 文档仍会退回 4-byte Rune 路径。

### 影响估算

| 输入规模 | rune 数组占用 | 实际峰值（含 ArrayList 副本） | tinyxml2 同输入峰值 |
|---|---|---|---|
| 1 MB ASCII | ~4 MB | ~6 MB | ~1 MB（in-place） |
| 5 MB ASCII | ~20 MB | ~30 MB | ~5 MB |
| 中文密集 1 MB | ~4 MB（每字符 3 字节 UTF-8 → 4 字节 UTF-32） | ~6 MB | ~1 MB |

实测 `parse` 速度差距中"Rune 解码 + 4× 内存带宽"是常驻 30~50% 因素。ASCII
快路径只是规避最常见英文 XML 的解码开销，不能解决 Unicode 文档的结构性内存放大。

### 改进建议

| 方案 | 复杂度 | 受益方 |
|---|---|---|
| `String` 暴露 `func bytesView(): Array<Byte>` 零拷贝字节视图（read-only） | 低 | 任意字节扫描密集型库 |
| `String` 暴露 `func indexCodepoint(byteOffset: Int64): Rune` + `func nextCodepointOffset(...)` 流式 API | 中 | XML/JSON/CSV/SAX |
| 引入 `RuneCursor` / `Utf8Cursor` 标准类型（参考 Rust `core::str::Chars`） | 中 | 长期 |

---

## P1-2：闭包参数触发堆分配

### 症状

任何接受闭包参数的函数（如自定义 `skipWhile(pred: (Rune) -> Bool)`）在调用点
都需要把闭包对象装进堆——即使闭包不捕获任何变量也无逃逸。
对每秒数百万次的 hot loop（XML parser 的字符判定循环、escape 扫描、
`ArrayList.filter` 等），这是真实可见的 GC 压力。

### 复现路径

老版本（已被 workaround 替换）：

```cangjie
// src/parser/source_cursor.cj —— 通用 skipWhile，每次调用都分配 closure
func skipWhile(pred: (Rune) -> Bool): Unit { ... }

// 调用点 1
cur.skipWhile(isNameChar)               // 函数引用 → callable adapter

// 调用点 2
cur.skipWhile { r => r != CH_LT }       // 显式 lambda

// 调用点 3：捕获了局部变量 quoteCh
cur.skipWhile { r => r != quoteCh && r != CH_LT }
```

### 已尝试 workaround

**手动展开为特化非闭包方法**——在库代码里复制三份逻辑：

```cangjie
// src/parser/source_cursor.cj:137~  现状
func skipNameChars(): Unit { ... }                   // 替换 skipWhile(isNameChar)
func skipUntilLt(): Unit { ... }                     // 替换 skipWhile { r => r != CH_LT }
func skipAttrValueChars(quoteCh: Rune): Bool { ... } // 替换 quote 捕获版
```

**实测收益**：对 `parse` config_large 加速 21%；其它解析维度 12%~35%。
也就是说**单是闭包分配本身就吃掉了 20% 左右的 parse 时间**。这只是一个
parser，可以预期所有字符级 DSL 都有同等量级损耗。

### 影响估算

- `skipWhile` 类调用若改回闭包版本，`parse` config_large: 440 ms → 530 ms
  （+20%），`parse` deep_small: 0.29 ms → 0.38 ms（+31%）。
- 写库的人为了规避只能"为每个谓词写一份特化方法"，导致代码重复，与"高阶函数"
  作为头等公民的语言定位相冲突。

### 改进建议

| 方案 | 复杂度 | 备注 |
|---|---|---|
| 编译器对**不捕获**的 closure literal 走栈分配 / 直接内联 | 中 | 至少能解决 `skipWhile { r => r != CH_LT }` 这类无捕获场景 |
| 引入 `@inline` lambda 注解（用户显式标注） | 低 | 给库作者一条明确的优化路径 |
| 提供 `Predicate<T>` 等 value-typed 函数对象，避免接口装箱 | 中 | 类似 Rust `Fn` trait monomorphization |

---

## P2-1：`Iterable<T>` / `Iterator<T>` 虚分发 + Option 装箱

### 症状

`for x in iterable` 展开为 `iter = iterable.iterator(); while (let Some(x) <- iter.next())`：
每次循环至少一次接口虚分发（`next()`）+ 一次 `Option<T>` 装箱。
迭代器对象本身也是堆分配。

### 复现路径

```cangjie
// src/writer/xml_writer.cj  序列化每个元素都触发
for (a in el.attributes()) {           // 构造 ArrayList.Iterator
    sink.write(...)
}
```

config_large.xml ≈ 50K 元素 × 平均 5 attrs，单次 serialize 触发 ~50K 次迭代器
对象分配 + ~250K 次 `next()` 接口调用。

### 已尝试 workaround

- 在 `XmlElement` 上新增 `attributeAt(i: Int64)` 索引访问 API。
- writer 改成 `for i in 0..el.attributeCount() { el.attributeAt(i) }`。

实测 **serialize catalog_large 由 240.8 ms → 129.1 ms（1.87×）**，差距完全
来自迭代器分配 + 虚分发。

### 影响估算

差距 = ~110 ms / 240 ms ≈ **45% serialize 时间**直接归因于 Iterator 抽象成本。

### 改进建议

- ArrayList / Array 的 `iterator()` 应被编译器特化为 inline 索引循环（类似 Rust 的
  `IntoIterator` for `&Vec<T>` 经过 monomorphization 后零成本）。
- `Option<T>` 在已知 `T: NonZero / 引用类型` 时应能 niche-pack，避免装箱。
- 至少应提供官方文档说明 "for-in 在 ArrayList 上有 O(n) 额外分配，热路径建议
  改索引"。

---

## P2-2：`String.runes()` 无零开销 byte 扫描替代品

### 症状

`escapeText` / `escapeAttribute` / `isAllWhitespace` / `decodeEntities` 等所有"扫
描特殊字符"逻辑，理论上 ASCII 单字节比对就够用，但 `runes()` 强制做 UTF-8 解码。
我们已经把这些路径手动重写为 `String.size` + `s[i]: Byte`（直接索引 UTF-8 字节）的
形式，但这个写法依赖 `s[i]` 返回 `Byte` 而非 `Rune` 的隐式约定，规范化程度低。

### 复现路径

```cangjie
// 当前写法（src/internal/text_escape.cj）
func needsTextEscape(s: String): Bool {
    let n = s.size
    var i = 0
    while (i < n) {
        let b = s[i]   // 依赖 String.[](Int64): Byte 重载
        if (b == ESCAPE_AMP || b == ESCAPE_LT || b == ESCAPE_GT) { return true }
        i++
    }
    false
}
```

### 改进建议

提供官方零开销 byte-iterator：

```cangjie
public extend String {
    public func bytesIter(): ByteIterator    // value type, no allocation
    public func containsByte(b: Byte): Bool  // 走 SIMD / strchr
}
```

---

## P2-3：`StringBuilder` 缺公开容量预分配 API

### 症状

```cangjie
// std.core 中现状
public class StringBuilder {
    public init()                       // 初始容量 32
    public init(str: String)            // 容量 = str 长度
    public init(value: Array<Rune>)     // 容量 = value.size
    // ❌ 没有 init(capacity: Int64)
}
```

`escapeText` 之类方法处理 1 MB 的待转义文本时，从 32 起步要扩容 ~15 次。

### 已尝试 workaround

我们试过把 `init(initialCapacity: Int64)` 加到自家 `StringXmlSink`，但
StringBuilder 内部容量无法控制，所以 hint 形同摆设：

```cangjie
public init(initialCapacity: Int64) {
    this.buffer = StringBuilder()
    let _ = initialCapacity   // ← 摆设
}
```

### 改进建议

`StringBuilder.init(capacity: Int64)` —— 与 `ArrayList` 的命名 / 行为完全对齐。

---

## P2-4：`HashMap<String, V>` 短键 hash 性能

### 症状

XML 属性名几乎都很短（`id`, `name`, `xmlns:xsi` 等 < 16 字节），但 `String.hashCode()`
似乎对每次 lookup 都做完整 UTF-8 字节扫描，没有 inline cache、没有针对短串的
特殊路径。`tryAddAttribute` 在 parse config_large 上单次开销 ~7 ms（实测 IDE 抽样）。

### 已尝试 workaround

- 合并两次 lookup 为一次（`tryAddAttribute` 一次 `attrIndex.get` + 命中分支
  跳过 put；未命中分支才 `attrIndex[k] = v`）。

### 改进建议

- `String.hashCode()` 缓存（first call lazily 计算，存到 String header 上）。
- 短字符串（≤ 8 / 16 字节）走 SIMD 一次性哈希。
- `HashMap.computeIfAbsent` 单次 lookup API 标准化。

---

## P3-1：`String → Array<Byte>` 和 `StringBuilder → Array<Byte>` 重复编码

### 症状

```cangjie
// src/io/save_xml.cj
let sink = StringXmlSink()              // 内部 StringBuilder（UTF-8）
let w = XmlWriter(sink, options: options)
w.writeDocument(doc)
sink.toString().toArray()               // ① toString 不拷贝；② toArray 把 UTF-8 又"编码"一次
```

文档明示 `StringBuilder.toString()` 不拷贝；但 `String.toArray()` 仍然会执行
"获取 UTF-8 字节"——既然内部就是 UTF-8，理论上应该是 zero-copy slice，
但目前每次都做一次完整字节拷贝。`writeXmlToBytes` 5 MB 输出场景下这是
~5 MB 多余的 memcpy。

### 改进建议

| API | 语义 |
|---|---|
| `StringBuilder.toUtf8Bytes(): Array<Byte>` | 一次性把内部 buffer 移交（move），后续 builder 失效 |
| `String.asUtf8Bytes(): Array<Byte>` | 零拷贝只读视图 |

---

## P3-2：缺 SIMD / strchr 等价 intrinsic

### 症状

我们的 `escapeText` / `needsTextEscape` 内层都是：

```cangjie
while (i < n) {
    let b = s[i]
    if (b == 0x26 || b == 0x3C || b == 0x3E) { ... }   // 5-way 比较
    i++
}
```

C 库 `strchr` / `memchr` / `_mm_cmpestri` 能做到每周期 16 字节并行比较。
这是仓颉端 escape 路径相对 tinyxml2 仍有 ~3× 差距的物理上限。

### 改进建议

提供 `std.simd` 包，至少先开放：

```cangjie
public func memchr(haystack: Array<Byte>, needle: Byte): Int64
public func memchr_any(haystack: Array<Byte>, needles: Array<Byte>): Int64
public func memcmp(a: Array<Byte>, b: Array<Byte>): Int64
```

底层使用编译器 intrinsic 自动选择 SSE / AVX / NEON。这一项受益面非常广（不只
XML，还包括 JSON / Protobuf / regex / template 等所有字节扫描场景）。

---

## 总结：库层已经做了什么 vs 还能做什么

| 维度 | 库层（cangjie_xml）已榨干 | 等价于"等 SDK 改进" |
|---|---|---|
| Rune 数组前置物化 | 已预估容量，并为全 ASCII 输入加直接字节转 Rune 快路径；Unicode 文档仍需字节流 parser（结构性大改）或等 P1-1 | **是** |
| 闭包热路径 | 已手工特化 3 个最热谓词；剩余 `skipWhile(pred)` 公开 API 仍保留 | 等 P1-2 |
| Iterator 分配 | 已加 `attributeAt(i)` 索引访问绕开；childNodes 走链表直访 | 等 P2-1 |
| 字节扫描 | 已字节级化，5-way 比较 ASCII 字符 | 等 P3-2（SIMD） |
| HashMap | 已合并两次 lookup 为一次 | 等 P2-4 |
| 输出零拷贝 | 已最小化中间副本，但末端 `toArray()` 无解 | 等 P3-1 |

**结论**：常见的"算法 / 数据结构"维度优化已经做满；继续把 cangjie_xml 推到
tinyxml2 的 1~3× 量级，需要仓颉编译器与标准库提供上述基础能力支持。
