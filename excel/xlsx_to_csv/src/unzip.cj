package xlsx_to_csv

import std.fs.*
import std.process.*

/**
 * 把 `.xlsx` 解压到临时目录。
 *
 * `.xlsx` 本质是 ZIP 容器——纯仓颉侧目前没有 ZIP 解压库（仓颉标准库
 * 覆盖 IO / 文本，但不含压缩格式），所以本模块调用宿主系统的 `unzip`。
 * 这并不违背"用 XML 库验证能力"的主旨：ZIP 容器只是外壳，真正被本项目
 * 消费的还是里面那些 OOXML 格式的 XML 文件。
 *
 * 不在这一层做"目录清理"——由上层（`main`）决定生命周期，必要时复用
 * 同一解压目录做多次实验。
 */
public func unzipXlsx(xlsxPath: String, destDir: String): Unit {
    let destPath = Path(destDir)
    if (!exists(destPath)) {
        Directory.create(destPath, recursive: true)
    }

    let (code, _, stderrBytes) = executeWithOutput(
        "unzip", ["-o", "-q", xlsxPath, "-d", destDir])
    if (code != 0) {
        let err = String.fromUtf8(stderrBytes).trimEnd()
        throw Exception("unzip ${xlsxPath} -> ${destDir} failed (code=${code}): ${err}")
    }
}

/**
 * 用 `mktemp -d` 创建一个独立临时目录，返回绝对路径。
 *
 * 上层可以选择复用调用方指定的目录（例如 `/tmp/xlsx_extract/`）；但默认行为
 * 应当是每次 run 用独立目录，避免旧残留文件混入解析流程。
 */
public func makeTempDir(prefix: String): String {
    let (code, stdoutBytes, _) = executeWithOutput("mktemp", ["-d", "-t", "${prefix}.XXXXXX"])
    if (code != 0) {
        throw Exception("mktemp failed with exit code ${code}")
    }
    String.fromUtf8(stdoutBytes).trimEnd()
}
