package xlsx_to_csv

import std.collection.*
import std.env.*
import std.fs.*
import std.io.*
import stdx.compress.zlib.*

/**
 * 把 `.xlsx` 解压到指定目录
 *
 * `.xlsx` 本质上是一个 ZIP 容器，内部条目要么以 **Stored**（method=0，原样
 * 写入）存储，要么以 **Deflate**（method=8）压缩。本模块自行解析 ZIP 外壳
 * （EOCD / Central Directory / Local File Header），对 Deflate 数据交由
 * `stdx.compress.zlib.DecompressInputStream` 处理，因此**无需调用宿主系统的
 * `unzip`**，Linux / Windows 上都可以直接运行
 *
 * 不在这一层做"目录清理"——由上层（`main`）决定生命周期，必要时复用
 * 同一解压目录做多次实验
 */
public func unzipXlsx(xlsxPath: String, destDir: String): Unit {
    let destPath = Path(destDir)
    if (!exists(destPath)) {
        Directory.create(destPath, recursive: true)
    }
    let bytes = File.readFrom(Path(xlsxPath))
    let entries = parseCentralDirectory(bytes)
    for (entry in entries) {
        extractEntry(bytes, entry, destDir)
    }
}

/**
 * 跨平台创建一个独立临时目录，返回绝对路径字符串
 *
 * 过去这里调用宿主的 `mktemp -d`，只在类 Unix 系统上可用。现在完全走仓颉
 * 标准库：`env.getTempDirectory()` 负责在 Linux / macOS / Windows 上拿到系统
 * 临时根（`$TMPDIR` / `%TEMP%` 等），再由 `Directory.createTemp` 生成唯一子
 * 目录，保证并发安全
 *
 * `prefix` 只用作**可读性分类目录**名，便于在系统临时目录里一眼认出本工具
 * 留下的解压产物；真正的唯一段由 `createTemp` 负责
 */
public func makeTempDir(prefix: String): String {
    let parent = getTempDirectory().join(prefix)
    if (!exists(parent)) {
        Directory.create(parent, recursive: true)
    }
    Directory.createTemp(parent).toString()
}

// ============================================================
// 以下为纯仓颉 ZIP 解析实现
// 参考：APPNOTE.TXT（PKWARE ZIP File Format Specification）4.3/4.4 章节
// 只覆盖 xlsx 里会出现的子集：单磁盘、Store / Deflate、无 ZIP64 扩展
// ============================================================

struct ZipEntry {
    let name: String
    let method: UInt16
    let compressedSize: Int64
    let localHeaderOffset: Int64

    init(name: String, method: UInt16, compressedSize: Int64, localHeaderOffset: Int64) {
        this.name = name
        this.method = method
        this.compressedSize = compressedSize
        this.localHeaderOffset = localHeaderOffset
    }
}

const EOCD_SIG: UInt32 = 0x06054b50u32
const CD_SIG: UInt32 = 0x02014b50u32
const LFH_SIG: UInt32 = 0x04034b50u32
const METHOD_STORED: UInt16 = 0u16
const METHOD_DEFLATE: UInt16 = 8u16

/**
 * 在文件末尾向前扫描 **End of Central Directory Record**，返回其在文件里的
 * 起始偏移。EOCD 至少 22 字节，尾部 comment 最长 65535 字节，所以最多往回
 * 找 65557 字节
 */
func findEocd(bytes: Array<Byte>): Int64 {
    let length = bytes.size
    if (length < 22) {
        throw Exception("not a zip archive: too small (${length} bytes)")
    }
    var start = length - 65557
    if (start < 0) { start = 0 }
    var index = length - 22
    while (index >= start) {
        if (readU32(bytes, index) == EOCD_SIG) {
            let commentLen = Int64(readU16(bytes, index + 20))
            if (index + 22 + commentLen == length) {
                return index
            }
        }
        index--
    }
    throw Exception("not a zip archive: EOCD signature not found")
}

/** 解析 Central Directory，返回所有条目（按 CD 中的出现顺序） */
func parseCentralDirectory(bytes: Array<Byte>): ArrayList<ZipEntry> {
    let eocdOff = findEocd(bytes)
    let totalEntries = Int64(readU16(bytes, eocdOff + 10))
    let cdSize = Int64(readU32(bytes, eocdOff + 12))
    let cdOff = Int64(readU32(bytes, eocdOff + 16))

    let entries = ArrayList<ZipEntry>()
    var pos = cdOff
    let cdEnd = cdOff + cdSize
    var seen: Int64 = 0
    while (pos < cdEnd && seen < totalEntries) {
        if (readU32(bytes, pos) != CD_SIG) {
            throw Exception("zip central directory corrupted at offset ${pos}")
        }
        let method = readU16(bytes, pos + 10)
        let compSize = Int64(readU32(bytes, pos + 20))
        let nameLen = Int64(readU16(bytes, pos + 28))
        let extraLen = Int64(readU16(bytes, pos + 30))
        let commentLen = Int64(readU16(bytes, pos + 32))
        let localOff = Int64(readU32(bytes, pos + 42))
        let name = String.fromUtf8(sliceBytes(bytes, pos + 46, nameLen))
        entries.add(ZipEntry(name, method, compSize, localOff))
        pos += 46 + nameLen + extraLen + commentLen
        seen++
    }
    entries
}

/** 提取单个条目到磁盘。目录条目按名创建目录；其余写文件 */
func extractEntry(bytes: Array<Byte>, entry: ZipEntry, destDir: String): Unit {
    // 防 zip-slip：拒绝绝对路径与 `..` 跳出
    if (!isSafeEntryName(entry.name)) {
        throw Exception("zip entry has unsafe path: ${entry.name}")
    }

    // 目录条目
    if (entry.name.endsWith("/")) {
        let dir = Path(destDir).join(entry.name)
        if (!exists(dir)) {
            Directory.create(dir, recursive: true)
        }
        return
    }

    // Local File Header：真正的数据起点 = localOffset + 30 + nameLen + extraLen
    let lo = entry.localHeaderOffset
    if (readU32(bytes, lo) != LFH_SIG) {
        throw Exception("zip local file header not found for '${entry.name}'")
    }
    let nameLen = Int64(readU16(bytes, lo + 26))
    let extraLen = Int64(readU16(bytes, lo + 28))
    let dataOff = lo + 30 + nameLen + extraLen
    let compData = sliceBytes(bytes, dataOff, entry.compressedSize)

    let outPath = Path(destDir).join(entry.name)
    let parent = outPath.parent
    if (!exists(parent)) {
        Directory.create(parent, recursive: true)
    }

    if (entry.method == METHOD_STORED) {
        File.writeTo(outPath, compData)
        return
    }
    if (entry.method == METHOD_DEFLATE) {
        File.writeTo(outPath, inflate(compData))
        return
    }
    throw Exception(
        "zip entry '${entry.name}' uses unsupported compression method ${entry.method}")
}

/** 用 stdx 的 Deflate 解压器把原始 deflate 字节流解压到内存字节 */
func inflate(compData: Array<Byte>): Array<Byte> {
    let src = ByteBuffer()
    src.write(compData)
    let stream = DecompressInputStream(src, wrap: DeflateFormat)
    let sink = ByteBuffer()
    let buf = Array<UInt8>(8192, repeat: 0)
    try {
        while (true) {
            let bytesRead = stream.read(buf)
            if (bytesRead <= 0) { break }
            sink.write(buf[..bytesRead])
        }
    } finally {
        stream.close()
    }
    sink.bytes().toArray()
}

/**
 * 判断 zip 条目名是否安全——拒绝绝对路径与任何 `..` 分段，避免 zip-slip
 */
func isSafeEntryName(name: String): Bool {
    if (name.size == 0) { return false }
    if (name.startsWith("/") || name.startsWith("\\")) { return false }
    for (part in name.split("/", removeEmpty: false)) {
        if (part == "..") { return false }
    }
    true
}

/** 从大 bytes 中切出 `[off, off+len)` 区间的拷贝，单点做越界检查 */
func sliceBytes(bytes: Array<Byte>, off: Int64, len: Int64): Array<Byte> {
    if (off < 0 || len < 0 || off + len > bytes.size) {
        throw Exception("zip slice out of range: off=${off}, len=${len}, size=${bytes.size}")
    }
    bytes[off..off + len]
}

/** 小端序读 UInt16 */
func readU16(buf: Array<Byte>, off: Int64): UInt16 {
    if (off < 0 || off + 2 > buf.size) {
        throw Exception("zip readU16 out of range: off=${off}, size=${buf.size}")
    }
    UInt16(buf[off]) | (UInt16(buf[off + 1]) << 8)
}

/** 小端序读 UInt32 */
func readU32(buf: Array<Byte>, off: Int64): UInt32 {
    if (off < 0 || off + 4 > buf.size) {
        throw Exception("zip readU32 out of range: off=${off}, size=${buf.size}")
    }
    UInt32(buf[off]) |
        (UInt32(buf[off + 1]) << 8) |
        (UInt32(buf[off + 2]) << 16) |
        (UInt32(buf[off + 3]) << 24)
}
