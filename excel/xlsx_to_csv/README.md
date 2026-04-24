# xlsx_to_csv — CangjieXML 的 xlsx 端到端示例

纯仓颉实现的 **xlsx → CSV** 转换器。目的不是做一款"更好用"的 xlsx 工具，
而是用一条**真实的业务链路**把 [`cangjie_xml`](../..) 库跑通：

- 默认命名空间 `xmlns="..."` + 带前缀属性 `r:id="..."`
- UTF-8 / BOM / XML 声明都走现实文档而不是挑过的 fixture
- sheet 文件体量中等（样例里最大的一张 sheet 原始 XML 约 680 KB）
- 需要**保留元素 / 属性的出现顺序**才能按行号 / 列号还原表格布局

能把这一个 demo 跑通，等价于验证了库的以下能力：Parser + IO + DOM + 属性
顺序保留 + 子元素迭代。

## 环境要求

- 仓颉 SDK 1.0.5，`cjc` / `cjpm` 已在 PATH 上。
  参考发行：<https://github.com/SunriseSummer/CangjieSDK/releases/download/1.0.5/cangjie-sdk-linux-x64-1.0.5.tar.gz>
- 仓颉扩展标准库 stdx 1.0.5.1（解压 xlsx 内部 Deflate 条目会用到
  `stdx.compress.zlib`）：
  - Linux x86_64：<https://github.com/SunriseSummer/CangjieSDK/releases/download/1.0.5/cangjie-stdx-linux-x64-1.0.5.1.zip>
  - 其它平台（Linux aarch64、Windows x86_64 等）请在同一发行页下载对应架构
    的压缩包。

下载后把内容解压到 `excel/xlsx_to_csv/stdx/` 下，使最终路径形如：

```
excel/xlsx_to_csv/stdx/dynamic/stdx/
├── libcangjie-stdx-...  (Linux: .so / macOS: .dylib / Windows: .dll)
├── ...
```

`cjpm.toml` 里用的是项目相对路径 `./stdx/dynamic/stdx`，**不绑定任何绝对
或沙箱路径**，开发机与 CI 都能直接复用。

## 用法

### 方式 1：一键跑通（Linux / macOS）

```bash
# 先 source 你装的仓颉 SDK 的 envsetup.sh，确保 `cjc` 在 PATH 上；
# 脚本检测到 stdx 缺失时会自动 `curl` 下载对应 zip 并解压到 ./stdx/。
bash excel/xlsx_to_csv/run.sh
```

自动把 `excel/*.xlsx` 依次转到 `excel/csv_out/<basename>/`，
并在运行前把 `stdx/dynamic/stdx` 加入 `LD_LIBRARY_PATH`。

如果需要覆盖下载地址，`CANGJIE_STDX_URL=<url> bash run.sh`。

### 方式 2：手工指定单个文件

```bash
cd excel/xlsx_to_csv
# 确保 stdx 已解压到 ./stdx/dynamic/stdx/
cjpm build
./target/release/bin/main <path/to/file.xlsx> <output/dir>
```

独立运行编译产物时需要把 stdx 动态库目录加入动态库搜索路径：

- Linux：`export LD_LIBRARY_PATH=$PWD/stdx/dynamic/stdx:$LD_LIBRARY_PATH`
- macOS：`export DYLD_LIBRARY_PATH=$PWD/stdx/dynamic/stdx:$DYLD_LIBRARY_PATH`
- Windows：把 `stdx\dynamic\stdx` 加入 `PATH`

如果用 `cjpm run -- <xlsx> <out>` 代替直接执行二进制，cjpm 会自动处理
动态库搜索路径，不必手动设置。

### 方式 3：Windows

```powershell
# 假设仓颉 SDK 的环境已配置好，cjc/cjpm 可用
cd excel\xlsx_to_csv
# 下载 Windows 版 stdx 发行包并解压到 .\stdx\（确保最终有 stdx\dynamic\stdx\）
cjpm build
$env:PATH = "$PWD\stdx\dynamic\stdx;$env:PATH"
.\target\release\bin\main.exe <path\to\file.xlsx> <output\dir>
```

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
| `src/unzip.cj`          | 纯仓颉 ZIP 解析 + `stdx.compress.zlib` Deflate 解压，不依赖宿主 `unzip`/`mktemp` |
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
