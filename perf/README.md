# perf — 三端性能对比

在统一的语料、统一的场景、统一的计时口径下，对比 CangjieXML（本仓库）、
tinyxml2 11.0.0（仓内 `.tinyxml2-11.0.0/`）与 Python `xml.etree`（标准库）的
解析、序列化、往返与遍历性能，输出 `perf/report.md`。

## 目录结构

```
perf/
├── fixtures/
│   └── generate.py      生成 9 份典型 XML（3 形态 × 3 规模）
├── python_bench/
│   └── bench.py         Python 端探针（xml.etree.ElementTree）
├── tinyxml2_bench/
│   ├── bench.cpp        C++ 端探针，链接 .tinyxml2-11.0.0
│   └── Makefile         g++ -O2 -DNDEBUG
├── cangjie_bench/
│   ├── cjpm.toml        path 依赖 fastxml
│   └── src/main.cj      仓颉端探针
├── bench.py             性能测试脚本：构建 + 跑三端 → out/*.json
├── report.py            报告生成脚本：out/*.json → report.md（含 SVG 图）
├── run.py               便捷入口：bench.py + report.py 串联
├── out/                 运行时产出：plan.json + 三份原始 JSON
├── report.md            自动生成的对比报告
└── README.md
```

## 跑法

完整流程（构建 + 跑基准 + 生成报告）：

```bash
python3 perf/run.py
```

按需分步运行：

```bash
python3 perf/bench.py     # 只跑基准，输出 perf/out/*.json
python3 perf/report.py    # 只读 JSON 重新生成 report.md（含 SVG 直方图）
```

## 环境要求

- 仓颉 SDK 1.0.5
  （[`cangjie-sdk-linux-x64-1.0.5.tar.gz`](https://github.com/SunriseSummer/CangjieSDK/releases/download/1.0.5/cangjie-sdk-linux-x64-1.0.5.tar.gz)
  解压到 `/opt/cangjie/`）
- `g++`（≥ C++17）、`make`、`python3` 在 PATH 中
- 无外部 Python 第三方依赖

## 设计取舍

### 为什么是这四个场景

`parse` / `serialize` / `roundtrip` 覆盖 XML 库的"读 / 写 / 闭环"主路径，
是任何 XML 库都该有的最小集。`traverse` 表征"读端"在工程里的典型负载——
"打开文件，扫一遍，提取字段"。

### 为什么用紧凑无空白的 fixture

每端的"解析空白行为"不一致（CangjieXML 默认 `Preserve`、Python ET 永远保留、
tinyxml2 自带 `COLLAPSE_WHITESPACE` 选项）。让 fixture 本身没有可"折叠 / 丢弃"
的空白，三端走同一条解析路径，差异完全归因于实现。

### 为什么平均 N 次而不是 min

`min` 适合表达"硬件上限"，平均更贴近"实际工程吞吐"。本基准的目标读者是评估
"用 fastxml 跑业务的耗时分布"，平均更有信号价值。每个单元跑足够多次（迭代
次数与字节量负相关，目标单元落在 0.05 ~ 5s 区间），噪声已被稀释。

## fixture / iterations 调参

`bench.py` 里的 `ITERATIONS` 表手工调出来：把每个 (lib, scenario, fixture)
单元的总耗时控制在 0.05 ~ 5 秒之间。改 fixture 规模时同步改这张表即可。

## 输出格式

`perf/report.md` 按场景出 4 张表，每张表行是 fixture / 列是三个库的"平均
单次毫秒数"，最后一组列是以 tinyxml2 为基准的"倍率"，并在每张表下附一张
SVG 直方图直观对比。

原始 JSON 落在 `perf/out/`：

```json
{
  "library": "fastxml",
  "results": [
    { "scenario": "parse", "fixture": "catalog_small.xml",
      "iterations": 500, "elapsed_ms_total": 121.9,
      "elapsed_ms_avg": 0.2438, "bytes": 16233 }
  ]
}
```

需要做更细的统计（百分位、分布画图等），直接基于这三份 JSON 二次加工即可。
