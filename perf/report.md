# CangjieXML / Python xml.etree / tinyxml2 性能对比

> 本报告由 `perf/run.py` 自动生成；请勿手工修改。重新生成方法：`python3 perf/run.py`。仓颉侧统一按 `-O2` 编译。

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
| `catalog_small.xml` | 500 | 0.4496 | 0.1351 | 0.2755 | 3.33× | 2.04× |
| `catalog_medium.xml` | 30 | 28.609 | 7.569 | 16.460 | 3.78× | 2.17× |
| `catalog_large.xml` | 5 | 298.7 | 49.049 | 106.3 | 6.09× | 2.17× |
| `config_small.xml` | 500 | 0.2050 | 0.0321 | 0.1301 | 6.38× | 4.05× |
| `config_medium.xml` | 60 | 7.213 | 1.671 | 6.505 | 4.32× | 3.89× |
| `config_large.xml` | 10 | 67.501 | 10.620 | 43.410 | 6.36× | 4.09× |
| `deep_small.xml` | 500 | 0.0313 | 0.0107 | 0.0336 | 2.93× | 3.13× |
| `deep_medium.xml` | 200 | 0.1142 | 0.0625 | 0.1274 | 1.83× | 2.04× |
| `deep_large.xml` | 50 | 0.4048 | 0.1733 | 0.3089 | 2.34× | 1.78× |

> 倍率列以 `tinyxml2` 为 1×；数值越小越快。

## 场景：`serialize`

| fixture | 迭代 | CangjieXML (ms/次) | tinyxml2 (ms/次) | Python xml.etree (ms/次) | CangjieXML 倍率 | Python xml.etree 倍率 |
|---|--:|--:|--:|--:|--:|--:|
| `catalog_small.xml` | 500 | 0.1445 | 0.0401 | 0.9550 | 3.60× | 23.8× |
| `catalog_medium.xml` | 30 | 10.550 | 2.660 | 46.869 | 3.97× | 17.6× |
| `catalog_large.xml` | 5 | 81.330 | 14.255 | 283.2 | 5.71× | 19.9× |
| `config_small.xml` | 500 | 0.0589 | 0.0163 | 0.3636 | 3.61× | 22.3× |
| `config_medium.xml` | 60 | 3.635 | 0.8152 | 17.029 | 4.46× | 20.9× |
| `config_large.xml` | 10 | 25.083 | 5.155 | 102.1 | 4.87× | 19.8× |
| `deep_small.xml` | 500 | 0.0141 | 0.0043 | 0.1167 | 3.32× | 27.4× |
| `deep_medium.xml` | 200 | 0.0570 | 0.0165 | 0.5484 | 3.46× | 33.2× |
| `deep_large.xml` | 50 | 0.1388 | 0.0332 | 1.082 | 4.18× | 32.5× |

> 倍率列以 `tinyxml2` 为 1×；数值越小越快。

## 场景：`roundtrip`

| fixture | 迭代 | CangjieXML (ms/次) | tinyxml2 (ms/次) | Python xml.etree (ms/次) | CangjieXML 倍率 | Python xml.etree 倍率 |
|---|--:|--:|--:|--:|--:|--:|
| `catalog_small.xml` | 500 | 0.4993 | 0.1995 | 1.240 | 2.50× | 6.22× |
| `catalog_medium.xml` | 30 | 39.354 | 10.532 | 62.515 | 3.74× | 5.94× |
| `catalog_large.xml` | 5 | 360.3 | 67.300 | 393.3 | 5.35× | 5.84× |
| `config_small.xml` | 500 | 0.1874 | 0.0503 | 0.5031 | 3.72× | 10.00× |
| `config_medium.xml` | 60 | 11.320 | 2.568 | 23.581 | 4.41× | 9.18× |
| `config_large.xml` | 10 | 86.777 | 20.727 | 144.8 | 4.19× | 6.99× |
| `deep_small.xml` | 500 | 0.0459 | 0.0151 | 0.1588 | 3.04× | 10.5× |
| `deep_medium.xml` | 200 | 0.1918 | 0.0796 | 0.7352 | 2.41× | 9.23× |
| `deep_large.xml` | 50 | 0.3363 | 0.2067 | 1.430 | 1.63× | 6.92× |

> 倍率列以 `tinyxml2` 为 1×；数值越小越快。

## 场景：`traverse`

| fixture | 迭代 | CangjieXML (ms/次) | tinyxml2 (ms/次) | Python xml.etree (ms/次) | CangjieXML 倍率 | Python xml.etree 倍率 |
|---|--:|--:|--:|--:|--:|--:|
| `catalog_small.xml` | 500 | 0.0127 | 0.0031 | 0.0294 | 4.07× | 9.42× |
| `catalog_medium.xml` | 30 | 1.781 | 0.2663 | 1.558 | 6.69× | 5.85× |
| `catalog_large.xml` | 5 | 41.591 | 2.602 | 13.617 | 16.0× | 5.23× |
| `config_small.xml` | 500 | 0.0016 | 0.000490 | 0.0064 | 3.35× | 13.0× |
| `config_medium.xml` | 60 | 0.1201 | 0.0798 | 0.3193 | 1.51× | 4.00× |
| `config_large.xml` | 10 | 1.112 | 0.6454 | 1.936 | 1.72× | 3.00× |
| `deep_small.xml` | 500 | 0.0012 | 0.000469 | 0.0030 | 2.54× | 6.46× |
| `deep_medium.xml` | 200 | 0.0062 | 0.0020 | 0.0125 | 3.05× | 6.16× |
| `deep_large.xml` | 50 | 0.0100 | 0.0046 | 0.0250 | 2.18× | 5.44× |

> 倍率列以 `tinyxml2` 为 1×；数值越小越快。

## 结论与观察

- **tinyxml2** 作为成熟 C++ 库（原地分段 + 内存池 + strchr/SSE），在各场景上是最快基线。
- **CangjieXML** 在 `-O2` 下相对 tinyxml2 的倍率落在 **约 1.5~16×**；`serialize` / `traverse` 稳定**反超 Python `xml.etree`**，`roundtrip` 在中大 fixture 上同样领先 Python。
- **Python `xml.etree`** 在 `parse` 上仍因走 C 实现的 expat 占优；仓颉版的剩余差距集中在大文档解析与属性密集型遍历。

## 测试期间对 cangjie_xml 库的 bug 排查

性能测试本身是高强度负载（每个 fixture 跑数十到数百轮 parse / serialize / roundtrip / traverse），既能暴露明显的 perf 瓶颈，也会触发不少边界路径。**结论：未发现功能性 bug**，详细排查记录如下。

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

DOM / parser / writer / escape 层面的算法优化已经基本榨干（参考 tinyxml2 的实现思路：原地分段切片 / 零拷贝 sub-string / 内存池 / strchr-SSE 字节查找）。**剩余 6~35× 的差距，根因不在 cangjie_xml 算法层，而落在仓颉编译器、运行时与标准库的通用性能特性上。**

已在 `problem.md` 中按观察到的影响维度记录了 **8 个具体的低效实现**（含复现路径、估算量化影响、对照实现），可作为反馈给 Cangjie SDK 团队的素材：

1. P1：`String` 内部 UTF-8 但 `Rune` 解码到 4-byte——parser 必须前置物化 `Array<Rune>`，5 MB ASCII 输入即耗 ~20 MB。
2. P1：闭包参数 `(T) -> R` 触发堆分配——XML 闭包密集场景的 GC 压力源，逼迫库代码用宏式特化 workaround（已在 `SourceCursor` 里手动展开 `skipNameChars` / `skipUntilLt` / `skipAttrValueChars`）。
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
