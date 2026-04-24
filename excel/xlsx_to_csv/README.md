# xlsx_to_csv — CangjieXML 的 xlsx 端到端示例

纯仓颉实现的 **xlsx → CSV** 转换器。目的不是做一款"更好用"的 xlsx 工具，
而是用一条**真实的业务链路**把 [`cangjie_xml`](../..) 库跑通：

- 默认命名空间 `xmlns="..."` + 带前缀属性 `r:id="..."`
- UTF-8 / BOM / XML 声明都走现实文档而不是挑过的 fixture
- sheet 文件体量中等（样例里最大的一张 sheet 原始 XML 约 680 KB）
- 需要**保留元素 / 属性的出现顺序**才能按行号 / 列号还原表格布局

能把这一个 demo 跑通，等价于验证了库的以下能力：Parser + IO + DOM + 属性
顺序保留 + 子元素迭代。

## 用法

```bash
# 方式 1：一键跑通——把 excel/*.xlsx 依次转到 excel/csv_out/<basename>/
bash excel/xlsx_to_csv/run.sh

# 方式 2：手工指定单个文件
source /opt/cangjie/envsetup.sh            # 或用你自己装的 SDK 1.0.5
cd excel/xlsx_to_csv
cjpm build
./target/release/bin/main <path/to/file.xlsx> <output/dir>
```

仓颉 SDK 参考发行：<https://github.com/SunriseSummer/CangjieSDK/releases/download/1.0.5/cangjie-sdk-linux-x64-1.0.5.tar.gz>

运行时依赖宿主系统的 `unzip` 命令——xlsx 本质是 ZIP 容器，而仓颉标准库
目前不内置解压器。除此之外整个转换管线都是纯仓颉。

## 输出

对每张 sheet 生成一个独立 CSV：

- 文件名 `<序号>_<sheet 名>.csv`，序号补零保证字典序与 workbook 中的
  `<sheets>` 顺序一致
- 编码 UTF-8，文件头带 BOM（方便 Windows / Mac 版 Excel 识别中文）
- 行分隔 `\r\n`，字段级 RFC 4180 引用
- 保留原表格**布局**：
  - 空行 / 空列 以空字段占位（按 `<dimension ref="...">` 的外包盒裁剪）
  - 共享字符串 `<sst>` / 内联字符串 `<is>` / 布尔 / 错误等 OOXML 单元格类型
    都被翻译为文本

不做：

- 数值格式化（日期序列号 → `"2012/7/2"`、小数位裁剪等），原因是 `styles.xml`
  的格式层跟 XML 解析能力没关系，留在调用方决定
- 公式求值
- 图片 / 图表 / 绘图对象

## 模块组织

| 文件 | 作用 |
|---|---|
| `src/main.cj`           | CLI 入口 + 调度 + 文件名兜底 |
| `src/unzip.cj`          | 调 `unzip` 解压 xlsx 到临时目录 |
| `src/workbook.cj`       | 解析 `xl/workbook.xml` + `workbook.xml.rels` 得到 sheet 列表 |
| `src/shared_strings.cj` | 解析 `xl/sharedStrings.xml`（含 rich text 拼接） |
| `src/sheet.cj`          | 解析 `xl/worksheets/sheetN.xml` → 二维 grid |
| `src/cell_ref.cj`       | `"A1"` / `"BC27"` 风格引用解析 |
| `src/csv_writer.cj`     | RFC 4180 CSV 序列化 |

每个文件都刻意控制在 **≤ 300 行** 内——和主库一样的单文件红线。

## 与 `e2etest/` 的关系

`e2etest/` 用的是项目自造的 fixture + Python 指纹对照。`xlsx_to_csv`
是对**陌生来源、中等体量**的真实 XML 文档做端到端验证，两者互补：前者
保证"和参考实现等价"，后者保证"能吃真实世界的 XML"。
