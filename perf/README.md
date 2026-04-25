# perf — 三端性能对比

> 在统一的语料、统一的场景、统一的计时口径下，对比
> **CangjieXML**（本仓库）/ **Python `xml.etree`**（标准库）/
> **tinyxml2 11.0.0**（仓内 `.tinyxml2-11.0.0/` C++ 库）的解析、序列化、
> 往返与遍历性能，输出 `perf/report.md`。

## 目录结构

```
perf/
├── fixtures/
│   └── generate.py        # 生成 9 份典型 XML：3 形态 × 3 规模
├── python_bench/
│   └── bench.py           # Python 端探针（xml.etree.ElementTree）
├── tinyxml2_bench/
│   ├── bench.cpp          # C++ 端探针，链接 .tinyxml2-11.0.0/tinyxml2.{cpp,h}
│   └── Makefile           # g++ -O2 -DNDEBUG
├── cangjie_bench/
│   ├── cjpm.toml          # path 依赖 cangjie_xml
│   └── src/main.cj        # 仓颉端探针
├── run.py                 # 入口：source SDK → 生成 → 构建 → 跑 → 出报告
├── out/                   # 运行时产出：plan.json 与 三份 raw JSON
├── report.md              # 自动生成的对比报告
└── README.md
```

## 跑法

```bash
python3 perf/run.py
```

脚本会：
1. 自动确保 `cjpm` 可用（必要时 `source /opt/cangjie/envsetup.sh`）。
2. `python3 fixtures/generate.py` —— 生成 9 份 fixture（catalog/config/deep ×
   small/medium/large）。
3. `make -C tinyxml2_bench` —— 构建 C++ 探针（`g++ -O2 -DNDEBUG`）。
4. `cjpm build` 构建仓颉探针，`perf/cangjie_bench/cjpm.toml` 已显式配置 `-O2`。
5. 串行跑三端探针 → 三份 JSON 计时。
6. 汇总写入 `perf/report.md`。

要求：
- 仓颉 SDK **1.0.5**（如未安装：
  `https://github.com/SunriseSummer/CangjieSDK/releases/download/1.0.5/cangjie-sdk-linux-x64-1.0.5.tar.gz`，
  解压到 `/opt/cangjie/`）。
- `g++` (≥ C++17)、`make`、`python3` 在 PATH 中。
- 无外部 Python 第三方依赖。

## 设计取舍

### 为什么是这四个场景？

`parse` / `serialize` / `roundtrip` 覆盖 XML 库的"读 / 写 / 闭环"三条主路径，
是任何 XML 库都该有的最小集。`traverse` 是真实工程里"读端"的典型负载——
"打开文件，扫一遍，提取你想要的字段"——在三端表达力不一致时（visitor /
iter / walk lambda），把"主路径里的纯访问成本"测出来比"闭门构造"更接近实际
体感。

故意**不**包含的场景：
- 美化输出 / 自定义缩进：换行模板纯属字符串拼接，三端差异主要由 IO 模式
  决定，不能反映 XML 库本身的处理能力。
- 命名空间 / DOCTYPE / 处理指令：三端支持深度不同（CangjieXML 走 `XmlUnknown`、
  Python ET 直接忽略、tinyxml2 提供 `XMLUnknown`），同语料同语义难以保证。

### 为什么用紧凑无空白的 fixture？

每端的"解析空白行为"略有差异（CangjieXML 默认 `Preserve`、Python ET 永远
保留、tinyxml2 自带 `COLLAPSE_WHITESPACE` 选项）。让 fixture 本身没有可"折叠 /
丢弃"的空白，三端走的就是同一条解析路径，测出来的差异完全归因于实现，不被
语义偏差污染。

### 为什么平均 N 次而不是 min？

工程基准里 `min` 适合表达"硬件上限"，平均更贴近"实际工程吞吐"。
本 perf 的目标读者是评估"我的项目用 cangjie_xml 跑业务时的耗时分布"，
平均更有信号价值。每个单元跑足够多次（迭代次数与字节量负相关，目标单元
落在 0.05 ~ 5s 区间），噪声已被稀释，结果稳定。

## fixture / iterations 调参

`run.py` 里的 `ITERATIONS` 表是手工调出来的：把每个 (lib, scenario, fixture)
单元的总耗时控制在 0.05 ~ 5 秒之间——上限避免一次跑下来太慢，下限避免计时
分辨率噪声盖过真实差异。改 fixture 规模时同步改这张表即可。

## 输出格式

`perf/report.md` 按场景出 4 张表，每张表行是 fixture / 列是三个库的"平均单次
毫秒数"，最后一组列是以 tinyxml2 为基准的"倍率"。报告底部还会附上观察与
后续优化方向。

原始 JSON 落在 `perf/out/`：

```json
{
  "library": "cangjie_xml",
  "results": [
    { "scenario": "parse", "fixture": "catalog_small.xml",
      "iterations": 500, "elapsed_ms_total": 3209.85,
      "elapsed_ms_avg": 6.4197, "bytes": 16233 },
    ...
  ]
}
```

需要做更细的统计（百分位、分布画图等），直接基于这三份 JSON 二次加工即可。
