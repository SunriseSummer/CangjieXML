用法：

```shell
cjpm build
./target/release/bin/main <path/to/file.xlsx> <output/dir>

# 或
cjpm run --run-args "<path/to/file.xlsx> <output/dir>"
```

原理：使用仓颉 stdx.compress.zlib 解压 xlsx，然后引用根目录中的仓颉 xml 库去解析 excel 包中的各个 xml 文件，最终提取转换为 csv 文本表示。