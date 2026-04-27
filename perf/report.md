# 性能对比：CangjieXML / tinyxml2 / Python xml.etree

> 由 `perf/report.py` 自动生成，请勿手工修改。
> 重新生成：先 `python3 perf/bench.py` 跑基准，再 `python3 perf/report.py` 出报告。

## 测试方法

- 三端共享同一组 fixture（`perf/fixtures/`）：紧凑 UTF-8 XML，覆盖目录型 / 属性密集型 / 深嵌套三种形态，每种 small / medium / large 三档共 9 份。
- 四个场景：`parse` 解析为 DOM、`serialize` 序列化为字节、`roundtrip` 解析后立即序列化、`traverse` 深度遍历整棵 DOM。
- 计时：单调时钟（C++ `steady_clock` / Python `perf_counter_ns` / 仓颉 `MonoTime`），单位毫秒；每个单元跑 N 次取平均，N 由 fixture 字节量决定，目标单元总耗时落在 0.05 ~ 5s 区间。
- 库版本：CangjieXML（本仓库，`-O2`）、tinyxml2 11.0.0（`-O2 -DNDEBUG`）、Python `xml.etree.ElementTree`（系统 Python）。

## fixture 概况

| fixture | 字节数 | 形态 |
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
| `catalog_small.xml` | 500 | 0.2147 | 0.1509 | 0.1820 | 1.42× | 1.21× |
| `catalog_medium.xml` | 30 | 8.232 | 8.361 | 12.350 | 0.98× | 1.48× |
| `catalog_large.xml` | 5 | 73.042 | 55.473 | 85.542 | 1.32× | 1.54× |
| `config_small.xml` | 500 | 0.0513 | 0.0298 | 0.0946 | 1.72× | 3.18× |
| `config_medium.xml` | 60 | 3.368 | 1.512 | 4.601 | 2.23× | 3.04× |
| `config_large.xml` | 10 | 24.392 | 10.312 | 34.501 | 2.37× | 3.35× |
| `deep_small.xml` | 500 | 0.0145 | 0.0100 | 0.0251 | 1.45× | 2.51× |
| `deep_medium.xml` | 200 | 0.0408 | 0.0623 | 0.0946 | 0.66× | 1.52× |
| `deep_large.xml` | 50 | 0.0817 | 0.1623 | 0.2402 | 0.50× | 1.48× |

> 倍率列以 `tinyxml2` 为 1×；数值越小越快。

![parse 场景对比直方图](charts/parse.svg)

## 场景：`serialize`

| fixture | 迭代 | CangjieXML (ms/次) | tinyxml2 (ms/次) | Python xml.etree (ms/次) | CangjieXML 倍率 | Python xml.etree 倍率 |
|---|--:|--:|--:|--:|--:|--:|
| `catalog_small.xml` | 500 | 0.1450 | 0.0373 | 0.7860 | 3.89× | 21.1× |
| `catalog_medium.xml` | 30 | 7.015 | 2.684 | 39.011 | 2.61× | 14.5× |
| `catalog_large.xml` | 5 | 51.184 | 14.009 | 236.5 | 3.65× | 16.9× |
| `config_small.xml` | 500 | 0.0473 | 0.0139 | 0.3051 | 3.41× | 22.0× |
| `config_medium.xml` | 60 | 2.679 | 0.6948 | 14.451 | 3.86× | 20.8× |
| `config_large.xml` | 10 | 17.654 | 4.353 | 88.522 | 4.06× | 20.3× |
| `deep_small.xml` | 500 | 0.0114 | 0.0039 | 0.0942 | 2.90× | 24.1× |
| `deep_medium.xml` | 200 | 0.0448 | 0.0152 | 0.5135 | 2.94× | 33.8× |
| `deep_large.xml` | 50 | 0.0883 | 0.0317 | 1.017 | 2.79× | 32.1× |

> 倍率列以 `tinyxml2` 为 1×；数值越小越快。

![serialize 场景对比直方图](charts/serialize.svg)

## 场景：`roundtrip`

| fixture | 迭代 | CangjieXML (ms/次) | tinyxml2 (ms/次) | Python xml.etree (ms/次) | CangjieXML 倍率 | Python xml.etree 倍率 |
|---|--:|--:|--:|--:|--:|--:|
| `catalog_small.xml` | 500 | 0.2564 | 0.2179 | 0.9664 | 1.18× | 4.44× |
| `catalog_medium.xml` | 30 | 17.099 | 11.314 | 49.588 | 1.51× | 4.38× |
| `catalog_large.xml` | 5 | 141.2 | 72.189 | 325.3 | 1.96× | 4.51× |
| `config_small.xml` | 500 | 0.0911 | 0.0449 | 0.4045 | 2.03× | 9.01× |
| `config_medium.xml` | 60 | 5.755 | 2.246 | 19.085 | 2.56× | 8.50× |
| `config_large.xml` | 10 | 33.731 | 22.325 | 120.6 | 1.51× | 5.40× |
| `deep_small.xml` | 500 | 0.0213 | 0.0142 | 0.1213 | 1.50× | 8.55× |
| `deep_medium.xml` | 200 | 0.0853 | 0.0733 | 0.6607 | 1.16× | 9.01× |
| `deep_large.xml` | 50 | 0.1716 | 0.1951 | 1.293 | 0.88× | 6.63× |

> 倍率列以 `tinyxml2` 为 1×；数值越小越快。

![roundtrip 场景对比直方图](charts/roundtrip.svg)

## 场景：`traverse`

| fixture | 迭代 | CangjieXML (ms/次) | tinyxml2 (ms/次) | Python xml.etree (ms/次) | CangjieXML 倍率 | Python xml.etree 倍率 |
|---|--:|--:|--:|--:|--:|--:|
| `catalog_small.xml` | 500 | 0.0187 | 0.0045 | 0.0263 | 4.14× | 5.82× |
| `catalog_medium.xml` | 30 | 0.5819 | 0.2280 | 1.396 | 2.55× | 6.12× |
| `catalog_large.xml` | 5 | 4.826 | 3.233 | 12.772 | 1.49× | 3.95× |
| `config_small.xml` | 500 | 0.0014 | 0.000637 | 0.0052 | 2.26× | 8.20× |
| `config_medium.xml` | 60 | 0.0766 | 0.0430 | 0.3144 | 1.78× | 7.31× |
| `config_large.xml` | 10 | 0.5671 | 0.4121 | 1.705 | 1.38× | 4.14× |
| `deep_small.xml` | 500 | 0.000822 | 0.000353 | 0.0024 | 2.33× | 6.87× |
| `deep_medium.xml` | 200 | 0.0033 | 0.0014 | 0.0108 | 2.37× | 7.85× |
| `deep_large.xml` | 50 | 0.0065 | 0.0028 | 0.0227 | 2.33× | 8.08× |

> 倍率列以 `tinyxml2` 为 1×；数值越小越快。

![traverse 场景对比直方图](charts/traverse.svg)

---

原始 JSON：`perf/out/{cangjie,tinyxml2,python}.json`。
