# 性能对比：CangjieXML / tinyxml2 / Python xml.etree

> 由 `perf/report.py` 自动生成，请勿手工修改。

## 测试方法

- 形态：目录文档、属性密集型、深嵌套，各 small / medium / large 共 9 份 fixture（`perf/fixtures/`）。
- 场景：`parse` 解析、`serialize` 序列化、`roundtrip` 解析+序列化、`traverse` 深度遍历。
- 计时：单调时钟，毫秒为单位；每单元跑 N 次取均值，N 由 fixture 字节量自适应至 0.05–5 s。
- 库版本：CangjieXML（本仓库，`-O2`）、tinyxml2 11.0.0（`-O2 -DNDEBUG`）、Python `xml.etree.ElementTree`。
- 结果表中 “×” 为相对 `tinyxml2` 的耗时倍率，越小越快；图表条长按各 fixture 内最大值归一化，尾部数值为实际 ms。

## fixture 概况

| fixture | 字节数 | 形态 |
|---|--:|---|
| `catalog_small.xml` | 16,233 | 目录文档（条目 + 属性 + 文本） |
| `catalog_medium.xml` | 831,828 | 目录文档（条目 + 属性 + 文本） |
| `catalog_large.xml` | 5,041,750 | 目录文档（条目 + 属性 + 文本） |
| `config_small.xml` | 6,162 | 配置文件（属性密集，几乎无文本） |
| `config_medium.xml` | 308,448 | 配置文件（属性密集，几乎无文本） |
| `config_large.xml` | 1,875,326 | 配置文件（属性密集，几乎无文本） |
| `deep_small.xml` | 912 | 深嵌套（递归路径、栈深度） |
| `deep_medium.xml` | 3,912 | 深嵌套（递归路径、栈深度） |
| `deep_large.xml` | 8,112 | 深嵌套（递归路径、栈深度） |

## 场景：`parse`

| fixture | N | CangjieXML | tinyxml2 | Python xml.etree | CangjieXML × | Python xml.etree × |
|---|--:|--:|--:|--:|--:|--:|
| `catalog_small.xml` | 500 | 0.1979 | 0.1520 | 0.1837 | 1.30× | 1.21× |
| `catalog_medium.xml` | 30 | 9.543 | 8.291 | 12.730 | 1.15× | 1.54× |
| `catalog_large.xml` | 20 | 74.550 | 55.411 | 87.387 | 1.35× | 1.58× |
| `config_small.xml` | 500 | 0.0528 | 0.0303 | 0.0961 | 1.74× | 3.17× |
| `config_medium.xml` | 60 | 2.422 | 1.507 | 4.656 | 1.61× | 3.09× |
| `config_large.xml` | 20 | 20.007 | 10.418 | 35.489 | 1.92× | 3.41× |
| `deep_small.xml` | 500 | 0.0192 | 0.0098 | 0.0251 | 1.95× | 2.55× |
| `deep_medium.xml` | 200 | 0.0714 | 0.0579 | 0.0946 | 1.23× | 1.63× |
| `deep_large.xml` | 50 | 0.1433 | 0.1624 | 0.2428 | 0.88× | 1.49× |

![parse](charts/parse.svg)

## 场景：`serialize`

| fixture | N | CangjieXML | tinyxml2 | Python xml.etree | CangjieXML × | Python xml.etree × |
|---|--:|--:|--:|--:|--:|--:|
| `catalog_small.xml` | 500 | 0.1041 | 0.0384 | 0.8015 | 2.71× | 20.8× |
| `catalog_medium.xml` | 30 | 4.545 | 2.663 | 38.677 | 1.71× | 14.5× |
| `catalog_large.xml` | 20 | 37.300 | 13.568 | 235.3 | 2.75× | 17.3× |
| `config_small.xml` | 500 | 0.0264 | 0.0143 | 0.3036 | 1.85× | 21.3× |
| `config_medium.xml` | 60 | 1.482 | 0.7013 | 14.475 | 2.11× | 20.6× |
| `config_large.xml` | 20 | 11.127 | 4.510 | 88.615 | 2.47× | 19.6× |
| `deep_small.xml` | 500 | 0.0091 | 0.0038 | 0.0963 | 2.40× | 25.3× |
| `deep_medium.xml` | 200 | 0.0346 | 0.0153 | 0.5149 | 2.26× | 33.6× |
| `deep_large.xml` | 50 | 0.0704 | 0.0304 | 1.012 | 2.32× | 33.3× |

![serialize](charts/serialize.svg)

## 场景：`roundtrip`

| fixture | N | CangjieXML | tinyxml2 | Python xml.etree | CangjieXML × | Python xml.etree × |
|---|--:|--:|--:|--:|--:|--:|
| `catalog_small.xml` | 500 | 0.2099 | 0.2191 | 0.9784 | 0.96× | 4.47× |
| `catalog_medium.xml` | 30 | 15.062 | 11.466 | 49.375 | 1.31× | 4.31× |
| `catalog_large.xml` | 20 | 106.4 | 73.202 | 318.0 | 1.45× | 4.34× |
| `config_small.xml` | 500 | 0.0721 | 0.0458 | 0.4074 | 1.58× | 8.90× |
| `config_medium.xml` | 60 | 4.211 | 2.286 | 19.245 | 1.84× | 8.42× |
| `config_large.xml` | 20 | 28.746 | 22.275 | 120.5 | 1.29× | 5.41× |
| `deep_small.xml` | 500 | 0.0279 | 0.0137 | 0.1252 | 2.03× | 9.13× |
| `deep_medium.xml` | 200 | 0.1061 | 0.0739 | 0.6588 | 1.44× | 8.92× |
| `deep_large.xml` | 50 | 0.2116 | 0.1904 | 1.284 | 1.11× | 6.74× |

![roundtrip](charts/roundtrip.svg)

## 场景：`traverse`

| fixture | N | CangjieXML | tinyxml2 | Python xml.etree | CangjieXML × | Python xml.etree × |
|---|--:|--:|--:|--:|--:|--:|
| `catalog_small.xml` | 500 | 0.0119 | 0.0044 | 0.0271 | 2.67× | 6.09× |
| `catalog_medium.xml` | 30 | 0.5983 | 0.2341 | 1.311 | 2.56× | 5.60× |
| `catalog_large.xml` | 20 | 8.747 | 2.760 | 8.499 | 3.17× | 3.08× |
| `config_small.xml` | 500 | 0.0014 | 0.000635 | 0.0050 | 2.25× | 7.94× |
| `config_medium.xml` | 60 | 0.1294 | 0.0427 | 0.2760 | 3.03× | 6.47× |
| `config_large.xml` | 20 | 0.6800 | 0.3320 | 1.600 | 2.05× | 4.82× |
| `deep_small.xml` | 500 | 0.0012 | 0.000349 | 0.0024 | 3.55× | 6.98× |
| `deep_medium.xml` | 200 | 0.0050 | 0.0012 | 0.0102 | 4.09× | 8.34× |
| `deep_large.xml` | 50 | 0.0098 | 0.0025 | 0.0212 | 3.88× | 8.38× |

![traverse](charts/traverse.svg)

---

原始 JSON：`perf/out/{cangjie,tinyxml2,python}.json`。
