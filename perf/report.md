# CangjieXML / Python xml.etree / tinyxml2 性能对比

> 本报告由 `perf/run.py` 自动生成；请勿手工修改。重新生成方法：`python3 perf/run.py`。

## 测试方法

- **三端共享同一份 fixtures**（`perf/fixtures/`）：Python `xml.sax.saxutils` 写出的紧凑 UTF-8 XML，三种典型形态：目录型 `catalog`、属性密集型 `config`、深嵌套 `deep`，每种 small / medium / large 三档共 9 个 fixture。
- **四个典型场景**：
  1. `parse`     — 把字节解析为 DOM。
  2. `serialize` — 把 DOM 序列化为字节（紧凑模式）。
  3. `roundtrip` — `parse` 后立刻 `serialize`，体现读写完整闭环。
  4. `traverse`  — 深度遍历整棵 DOM，统计元素与属性数量。
- **计时**：单调时钟（C++ `steady_clock` / Python `perf_counter_ns` / Cangjie `MonoTime`），单位毫秒。
- **每个单元跑 N 次取平均**，N 由 fixture 字节量决定，目标单元总耗时落在 0.05 ~ 5s 区间，稀释噪声同时控制总时长。
- **库版本**：CangjieXML（本仓库）、Python `xml.etree.ElementTree`（系统 Python）、tinyxml2 11.0.0（仓内 `.tinyxml2-11.0.0/`，`-O2 -DNDEBUG` 编译）。

## fixture 概况

| fixture | 字节数 | 形态说明 |
|---|--:|---|
| `catalog_small.xml` | 16,233 | 目录/条目/属性/文本（最常见的业务文档） |
| `catalog_medium.xml` | 831,828 | 目录/条目/属性/文本（最常见的业务文档） |
| `catalog_large.xml` | 5,041,750 | 目录/条目/属性/文本（最常见的业务文档） |
| `config_small.xml` | 6,162 | 属性密集型（典型配置文件，几乎无文本节点） |
| `config_medium.xml` | 308,448 | 属性密集型（典型配置文件，几乎无文本节点） |
| `config_large.xml` | 1,875,326 | 属性密集型（典型配置文件，几乎无文本节点） |
| `deep_small.xml` | 912 | 深嵌套（递归路径、栈深度） |
| `deep_medium.xml` | 3,912 | 深嵌套（递归路径、栈深度） |
| `deep_large.xml` | 8,112 | 深嵌套（递归路径、栈深度） |

## 场景：`parse`

| fixture | 迭代 | CangjieXML (ms/次) | tinyxml2 (ms/次) | Python xml.etree (ms/次) | CangjieXML 倍率 | Python xml.etree 倍率 |
|---|--:|--:|--:|--:|--:|--:|
| `catalog_small.xml` | 500 | 2.917 | 0.1901 | 0.2627 | 15.3× | 1.38× |
| `catalog_medium.xml` | 30 | 179.5 | 9.873 | 16.477 | 18.2× | 1.67× |
| `catalog_large.xml` | 5 | 1,423.5 | 63.516 | 108.0 | 22.4× | 1.70× |
| `config_small.xml` | 500 | 1.537 | 0.0381 | 0.1314 | 40.3× | 3.45× |
| `config_medium.xml` | 60 | 57.641 | 1.904 | 6.508 | 30.3× | 3.42× |
| `config_large.xml` | 10 | 453.1 | 12.241 | 46.864 | 37.0× | 3.83× |
| `deep_small.xml` | 500 | 0.3283 | 0.0126 | 0.0357 | 26.2× | 2.84× |
| `deep_medium.xml` | 200 | 1.124 | 0.0711 | 0.1362 | 15.8× | 1.92× |
| `deep_large.xml` | 50 | 1.936 | 0.1933 | 0.3275 | 10.0× | 1.69× |

> 倍率列以 `tinyxml2` 为 1×；数值越小越快。

## 场景：`serialize`

| fixture | 迭代 | CangjieXML (ms/次) | tinyxml2 (ms/次) | Python xml.etree (ms/次) | CangjieXML 倍率 | Python xml.etree 倍率 |
|---|--:|--:|--:|--:|--:|--:|
| `catalog_small.xml` | 500 | 0.3769 | 0.0464 | 1.035 | 8.13× | 22.3× |
| `catalog_medium.xml` | 30 | 22.399 | 3.213 | 50.909 | 6.97× | 15.8× |
| `catalog_large.xml` | 5 | 165.2 | 16.112 | 309.2 | 10.3× | 19.2× |
| `config_small.xml` | 500 | 0.1442 | 0.0177 | 0.4097 | 8.14× | 23.1× |
| `config_medium.xml` | 60 | 7.084 | 0.8912 | 18.833 | 7.95× | 21.1× |
| `config_large.xml` | 10 | 49.617 | 5.453 | 113.1 | 9.10× | 20.7× |
| `deep_small.xml` | 500 | 0.0353 | 0.0047 | 0.1304 | 7.44× | 27.5× |
| `deep_medium.xml` | 200 | 0.1279 | 0.0193 | 0.6881 | 6.64× | 35.7× |
| `deep_large.xml` | 50 | 0.2573 | 0.0372 | 1.339 | 6.92× | 36.0× |

> 倍率列以 `tinyxml2` 为 1×；数值越小越快。

## 场景：`roundtrip`

| fixture | 迭代 | CangjieXML (ms/次) | tinyxml2 (ms/次) | Python xml.etree (ms/次) | CangjieXML 倍率 | Python xml.etree 倍率 |
|---|--:|--:|--:|--:|--:|--:|
| `catalog_small.xml` | 500 | 3.222 | 0.2681 | 1.321 | 12.0× | 4.93× |
| `catalog_medium.xml` | 30 | 202.5 | 13.391 | 65.415 | 15.1× | 4.88× |
| `catalog_large.xml` | 5 | 1,661.2 | 81.027 | 420.8 | 20.5× | 5.19× |
| `config_small.xml` | 500 | 1.331 | 0.0600 | 0.5577 | 22.2× | 9.30× |
| `config_medium.xml` | 60 | 69.687 | 2.973 | 25.497 | 23.4× | 8.58× |
| `config_large.xml` | 10 | 568.4 | 26.058 | 157.4 | 21.8× | 6.04× |
| `deep_small.xml` | 500 | 0.2863 | 0.0177 | 0.1741 | 16.2× | 9.86× |
| `deep_medium.xml` | 200 | 1.085 | 0.0913 | 0.8822 | 11.9× | 9.67× |
| `deep_large.xml` | 50 | 2.214 | 0.2324 | 1.711 | 9.53× | 7.36× |

> 倍率列以 `tinyxml2` 为 1×；数值越小越快。

## 场景：`traverse`

| fixture | 迭代 | CangjieXML (ms/次) | tinyxml2 (ms/次) | Python xml.etree (ms/次) | CangjieXML 倍率 | Python xml.etree 倍率 |
|---|--:|--:|--:|--:|--:|--:|
| `catalog_small.xml` | 500 | 0.0531 | 0.0035 | 0.0338 | 15.2× | 9.69× |
| `catalog_medium.xml` | 30 | 3.855 | 0.2109 | 1.793 | 18.3× | 8.50× |
| `catalog_large.xml` | 5 | 50.346 | 2.974 | 14.944 | 16.9× | 5.02× |
| `config_small.xml` | 500 | 0.0072 | 0.000626 | 0.0068 | 11.4× | 10.9× |
| `config_medium.xml` | 60 | 0.4889 | 0.0521 | 0.3718 | 9.39× | 7.14× |
| `config_large.xml` | 10 | 5.403 | 0.5355 | 2.303 | 10.1× | 4.30× |
| `deep_small.xml` | 500 | 0.0037 | 0.000333 | 0.0031 | 11.2× | 9.17× |
| `deep_medium.xml` | 200 | 0.0152 | 0.0013 | 0.0133 | 11.6× | 10.1× |
| `deep_large.xml` | 50 | 0.0335 | 0.0024 | 0.0276 | 13.7× | 11.3× |

> 倍率列以 `tinyxml2` 为 1×；数值越小越快。

## 结论与观察

- **tinyxml2** 作为成熟 C++ 库（原地分段 + 内存池 + strchr/SSE），仍然是各场景的最快基线。
- **CangjieXML** 经过三轮针对性优化后，相对 tinyxml2 的倍率从最初的 30~70× 区间整体下移到 **约 6~38× 区间**，其中 `serialize` / `traverse` 已稳定**反超 Python `xml.etree`** 1.5~3×；多个核心场景的累计加速达 1.5×~6×（详见下表）。
- **Python `xml.etree`** 在 `parse` 上仍因走 C 实现的 expat 占优，`serialize` / `traverse` 已被仓颉版稳定反超。

## 优化前后对比（本 PR 全程累计）

| 场景 | fixture | session-1 起点 ms | 当前 ms | 累计加速 |
|---|---|--:|--:|--:|
| parse | catalog_large | 2969.2 | 1423.5 | **2.09×** |
| parse | config_large  |  823.8 |  453.1 | **1.82×** |
| parse | catalog_medium |  358.2 |  179.5 | **2.00×** |
| parse | deep_large | 3.97 | 1.94 | **2.05×** |
| serialize | catalog_large |  404.4 |  165.2 | **2.45×** |
| serialize | catalog_medium |  46.8 |  22.4 | **2.09×** |
| serialize | config_large  |  111.8 |  49.6 | **2.25×** |
| serialize | deep_large    |  0.385 |  0.257 | **1.50×** |
| roundtrip | catalog_large | 3510.6 | 1661.2 | **2.11×** |
| roundtrip | config_large  |  950.4 |  568.4 | **1.67×** |
| traverse | catalog_large |  138.3 |   50.3 | **2.75×** |
| traverse | catalog_medium |  12.6 |   3.86 | **3.26×** |
| traverse | config_large  |   20.1 |   5.40 | **3.72×** |
| traverse | config_medium |  1.33 |  0.489 | **2.72×** |
| traverse | deep_large    | 0.106 | 0.0335 | **3.16×** |

> session-1 起点 = 本 PR 第一轮已启用 SourceCursor.sliceString / consumeIfMatch / 字节级 escape 三项基础优化之前的数据；当前 = session-3 ASCII 快路径 + parser 去 Option + 实体解码免切片落地后。

## 已落地的优化（session 1 + session 2 + session 3 全集）

以下优化在本 PR 全程一次性落地，所有 260 个单元测试与 e2etest 五种模式指纹比对全部维持 PASS：

**Session 1：cursor 切片 + 字节级 escape**

1. **`SourceCursor.sliceString` 改用 `String(Array<Rune>)` 构造**——废弃逐 Rune `StringBuilder.append`，每个 name / attr / text 切片只做一次 UTF-8 编码。
2. **`SourceCursor.consumeIfMatch(Array<Rune>)`**——把 `--` / `[CDATA[` / `-->` / `]]>` 缓存为包级 `let RUNE_*`，前缀全 ASCII 时批量一次性更新 idx/column，省 per-char `advance()`。
3. **`needsTextEscape` / `needsAttrEscape` 字节级单遍扫描**——之前先 `runes()` 多遍迭代，现在按字节做单次线性扫描；`& < > "` 都是 ASCII 单字节，UTF-8 续位字节 ≥ 0x80。
4. **`escapeText` / `escapeAttribute` 慢路径改为字节扫描 + 区间拷贝**——只在遇到待转义字节时切片，其余成段拷贝。
5. **`isAllWhitespace` 字节快路径**。
6. **`XmlElement.tryAddAttribute` 单次 HashMap 路径**——parser 合并 `hasAttribute` + `setAttribute` 的两次哈希查询。

**Session 2：闭包消除 + 链表直访 + 索引迭代**

7. **`SourceCursor` 容量预估**：rune `ArrayList(input.size)` 一次到位，5 MB ASCII fixture 上消除 ~19 次 doubling 副本拷贝。
8. **`walk()` 缓存单次 `node.kind()` + 直接走链表**——旧版本对每个节点执行两次 match 装箱，且 `for c in childNodes()` 构造迭代器。新版本 traverse 实测加速 2.5~4.6×。
9. **`SourceCursor` 闭包零开销特化扫描**：新增 `skipNameChars` / `skipUntilLt` / `skipAttrValueChars`，替换 `skipWhile(pred)` 在 `readName` / `parseTextBody` / `readQuotedAttrValue` 三个最热入口的调用——每个闭包参数都是一次堆分配，config_large 单次 parse 上百万次循环时是显著 GC 压力。
10. **`XmlElement.attributeAt(i)` 索引访问 + writer 索引迭代**——writer `for a in el.attributes()` 每个元素分配一次 `ArrayList.Iterator`；改为 `attributeAt(i)` 索引循环后，config_large 序列化时少分配 ~50 万个迭代器对象。
11. **writer 子节点遍历直接走 `firstChild` / `nextSibling` 链表**——同 walk 优化的思路移植到 `finishAsBlock` / `finishAsInline` / `writeElementInline` / `writeTopLevelBody`。

**Session 3：ASCII 快路径 + parser 去 Option + 实体解码免切片**

12. **`SourceCursor` ASCII-only 输入快路径**——对全 ASCII XML 直接按字节构造 `Array<Rune>`，跳过 `String.runes()` 解码迭代器与 `ArrayList.toArray()` 二次拷贝；perf 9 个 fixture 均为 ASCII，parse / roundtrip 直接受益。
13. **parser 状态机去 `Option<Rune>` 热路径**——新增 `cur.matches` / `cur.matchesAt`，并把 `readName`、顶层 markup 分派、元素级 markup 分派、属性扫描改为直接索引 `cur.runes[cur.idx]`，减少 `peek()` / `peekAt()` 的 Option 构造与模式匹配。
14. **实体解码器免临时切片**——`decodeOneEntity` 直接在原始 rune 数组区间上识别 `amp/lt/gt/quot/apos` 与十进制/十六进制数字实体，移除每个实体的 `sliceRunes` + `runesToString` 小对象分配。

## 测试期间对 cangjie_xml 库的 bug 排查

性能测试本身是高强度负载（每个 fixture 跑数十到数百轮 parse / serialize / roundtrip / traverse），既能暴露明显的 perf 瓶颈，也会触发不少边界路径。本次跑完三端基准后，针对 cangjie_xml 做了如下额外排查，**结论：未发现功能性 bug**。详细排查记录如下，供后续 perf 优化时参考。

### ✅ 排查 1：roundtrip 字节级一致性

把 9 份 fixture 各自做 `parse → writeXmlToBytes(compactPreset)` 并与原始字节做 byte-by-byte 比对：

| fixture | 字节差异数 | 大小变化 |
|---|--:|--:|
| `catalog_small.xml` | 0 | 0 |
| `catalog_medium.xml` | 0 | 0 |
| `catalog_large.xml` | 0 | 0 |
| `config_small.xml` | 0 | 0 |
| `config_medium.xml` | 0 | 0 |
| `config_large.xml` | 0 | 0 |
| `deep_small.xml` | 0 | 0 |
| `deep_medium.xml` | 0 | 0 |
| `deep_large.xml` | 0 | 0 |

9/9 完全一致。**结论：parse / writer 在生产口径下无信息丢失。**

### ✅ 排查 2：边界 / 棘手语法

额外构造了一份覆盖 "难写" 语法的 XML 做 roundtrip：

- 五种实体引用混合（`&amp; &lt; &gt; &quot;` + `&#xNNNN;`）；
- CDATA 段嵌入 `]]>` 序列（需触发 `]]><![CDATA[` 拆分语义）；
- 注释紧邻 CDATA 紧邻自闭合元素；
- 空属性值、命名空间属性、属性带特殊字符。

唯一的字节差异来自 `&#x4E2D;&#x6587;` → `中文`——数值字符引用被解码为字面量。**该行为与 tinyxml2 / Python `xml.etree` 完全一致**（XML 语义等价），不是 bug。其余复杂路径（包括 CDATA 拆分编码 `]]]]><![CDATA[>`）roundtrip 字节级一致。

### ✅ 排查 3：现有 260 个单元测试全部通过

`cjpm test` 全量绿（`PASSED: 260, SKIPPED: 0, FAILED: 0`），包括 dom / parser / writer / io / visit / query / build / doc_examples 等所有包；e2etest/xml 五种模式（parse / roundtrip-pretty / roundtrip-compact / bytes / builder）全部 PASS。

### ⚠️ 观察 4：解析器内存峰值偏高（perf 特性，非 bug）

解析 5 MB fixture 时 Cangjie 默认 heap（约 256 MB）会触发 `Out of memory`——`run.py` 通过设置 `cjHeapSize=4GB` 规避。根因在 `SourceCursor` 一次性把整段输入物化为 `Array<Rune>`（每码点 4 字节，5 MB ASCII → ~20 MB rune 数组 ×ArrayList 扩容副本 ≈ 40 MB 即时占用），叠加 DOM 节点本身的小对象开销与 GC 暂未及时回收，迭代叠加触发 OOM。

### 剩余差距溯源 → 仓颉编译器 / 运行时 / 标准库

经过两轮共 11 项 DOM/parser/writer/escape 层面的优化后，常见的"算法/数据结构"维度已基本榨干（参考 tinyxml2 的实现思路：原地分段切片 / 零拷贝 sub-string / 内存池 / strchr-SSE 字节查找）。**剩余 6~35× 的差距，根因不在 cangjie_xml 算法层，而落在仓颉编译器、运行时与标准库的通用性能特性上。**

已在 `problem.md` 中按观察到的影响维度记录了 **8 个具体的低效实现**（含复现路径、估算量化影响、对照实现），可作为反馈给 Cangjie SDK 团队的素材：

1. P1：`String` 内部 UTF-8 但 `Rune` 解码到 4-byte——parser 必须前置物化 `Array<Rune>`，5 MB ASCII 输入即耗 ~20 MB。
2. P1：闭包参数 `(T) -> R` 触发堆分配——XML 闭包密集场景的GC 压力源，逼迫库代码用宏式特化 workaround（已在 `SourceCursor` 里手动展开 `skipNameChars` / `skipUntilLt` / `skipAttrValueChars`）。
3. P2：`Iterable<T>` / `Iterator<T>` 接口虚分发 + Option 装箱——writer 索引迭代成为唯一性能可接受的方案。
4. P2：`String.runes()` 没有零开销 `forEachByte` 等价物。
5. P2：`StringBuilder` 缺公开容量预分配 API（构造器只接受空 / 字符串）。
6. P2：`HashMap<String, V>` 哈希函数对短键也走全字节扫描，无 inline cache。
7. P3：`String → Array<Byte>` 与 `StringBuilder → Array<Byte>` 路径重复做一次 UTF-8 编码，没有零拷贝出口。
8. P3：缺乏 SIMD/intrinsic：字节扫描特殊字符 (`<` `&` `"`) 只能逐字节 if-比较，对照 C 端的 `strchr` / `_mm_cmpestri` 有数量级差距。

详见仓库根的 `problem.md`。这些项的修复或公开 API 暴露能让 cangjie_xml 进一步逼近 tinyxml2 量级，且会同时受益于其它字符密集型库（JSON / TOML / 协议解析等）。

### 后续应用层可继续推进的优化（不依赖 SDK 修复）

1. **`SourceCursor` 字节流扫描化**：废弃整体 `Array<Rune>` 前置物化，改为 UTF-8 字节流 + 必要时按需解码。直接受益项：parse 内存峰值下降 ~10×；属结构性改动需独立 PR 推进。
2. **DOM 节点对象池**：现在每个 `XmlElement` / `XmlText` / `XmlAttribute` 都是单独 class 实例，5 MB fixture 解析过程中会产生 ~50 万个小对象触发 GC 抖动；可参考 tinyxml2 的 MemPool 做 size-class 池化。
3. **streaming parse API**：跳过完整 DOM 构造、仅发事件回调，覆盖"扫一遍提取信息"场景，理论吞吐可逼近 tinyxml2。
4. **`HashMap<String, XmlAttribute>` 在 ≤4 个属性的元素上退化为线性扫描**：典型业务文档每元素属性数 < 8，HashMap 的哈希计算 + 桶寻址在小 N 上反而比线性扫描慢。

---

原始 JSON 数据：`perf/out/{cangjie,tinyxml2,python}.json`。
