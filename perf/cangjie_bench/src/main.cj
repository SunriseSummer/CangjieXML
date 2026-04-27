package cangjie_bench

import std.collection.*
import std.fs.*
import std.time.*
import tinyxml2.dom.*
import tinyxml2.io.*
import tinyxml2.visit.*
import tinyxml2.writer.*

/**
 * tinyxml2 端 perf 探针——与 python_bench / tinyxml2_bench 共用同一份 fixtures
 * + plan.json，输出与之结构一致的 JSON 到 stdout。
 *
 * 四个典型场景：
 *   1. parse:      bytes -> XmlDocument                （Parser + IO）
 *   2. serialize:  XmlDocument -> bytes（compact 模式）（Writer）
 *   3. roundtrip:  parse -> serialize 回环             （读写闭环）
 *   4. traverse:   walk 整棵 DOM，统计元素 + 属性数      （读端典型负载）
 *
 * 设计取舍：
 * - 用 `MonoTime` 做计时：不受系统时钟调整影响，纳秒分辨率。
 * - serialize / traverse 用一份预解析过的 doc 重复跑——这两个场景应只测自身耗时，
 *   不应把 parse 的成本算进去（与 python / tinyxml2 端做法一致）。
 * - 所有 IO 走 `parseXmlBytes` / `writeXmlToBytes`：避免文件 IO 噪声污染纯 XML
 *   解析与序列化的耗时；与 tinyxml2 端 `Parse(buf, size)` 对齐。
 * - "副作用 sink"用累加 Int64 防止编译器把循环优化为空——Counter.total 与
 *   serialized.size 都被追加到 `sink` 上。
 *
 * 用法：cangjie_bench <fixture_dir> <plan.json>
 *   plan.json: [{ "file": "catalog_small.xml", "iterations": 1000 }, ...]
 */
main(args: Array<String>): Int64 {
    if (args.size < 2) {
        println("usage: cangjie_bench <fixture_dir> <plan.json>")
        return 2
    }
    let dir = args[0]
    let planPath = args[1]
    let plan = parsePlan(File.readFrom(Path(planPath)))

    let json = StringBuilder()
    json.append("{\n  \"library\": \"tinyxml2\",\n  \"results\": [\n")
    var first = true
    for (entry in plan) {
        runOne(json, first, dir, entry)
        first = false
    }
    json.append("\n  ]\n}\n")
    print(json.toString())
    0
}

/** plan.json 单条记录。 */
class PlanEntry {
    PlanEntry(let file: String, let iterations: Int64) {}
}

/**
 * 极简 JSON 解析——只够吃我们自己生成的 plan.json，
 * 与 tinyxml2_bench 端思路对齐（不引第三方依赖）。
 */
func parsePlan(bytes: Array<Byte>): ArrayList<PlanEntry> {
    let text = String.fromUtf8(bytes)
    let entries = ArrayList<PlanEntry>()
    var pos = 0
    while (true) {
        let f = indexOf(text, "\"file\"", pos)
        if (f < 0) { break }
        let colon = indexOfAsciiChar(text, r':', f)
        let q1 = indexOfAsciiChar(text, r'"', colon)
        let q2 = indexOfAsciiChar(text, r'"', q1 + 1)
        let file = text[q1 + 1..q2]

        let it = indexOf(text, "\"iterations\"", q2)
        let colon2 = indexOfAsciiChar(text, r':', it)
        var end = colon2 + 1
        while (end < text.size && !isDelim(text[end])) { end++ }
        let num = text[colon2 + 1..end].trimAscii()
        let iters = parseInt64(num)

        entries.add(PlanEntry(file, iters))
        pos = end
    }
    entries
}

func runOne(out: StringBuilder, isFirst: Bool, dir: String, e: PlanEntry): Unit {
    let path = "${dir}/${e.file}"
    let raw = File.readFrom(Path(path))
    let bytes = raw.size
    let iters = e.iterations

    // 预解析一份给 serialize / traverse 用
    let preDoc = parseXmlBytes(raw)
    var sink: Int64 = 0
    var localFirst = isFirst

    // 1. parse
    let t0 = MonoTime.now()
    for (_ in 0..iters) {
        let d = parseXmlBytes(raw)
        sink += if (d.rootElement.isSome()) { 1 } else { 0 }
    }
    let t1 = MonoTime.now()
    emit(out, localFirst, "parse", e.file, iters, durationMs(t1 - t0), bytes)
    localFirst = false

    // 2. serialize
    let opts = XmlWriteOptions.compactPreset()
    let t2 = MonoTime.now()
    for (_ in 0..iters) {
        let buf = writeXmlToBytes(preDoc, opts)
        sink += buf.size
    }
    let t3 = MonoTime.now()
    emit(out, localFirst, "serialize", e.file, iters, durationMs(t3 - t2), bytes)

    // 3. roundtrip
    let t4 = MonoTime.now()
    for (_ in 0..iters) {
        let d = parseXmlBytes(raw)
        let buf = writeXmlToBytes(d, opts)
        sink += buf.size
    }
    let t5 = MonoTime.now()
    emit(out, localFirst, "roundtrip", e.file, iters, durationMs(t5 - t4), bytes)

    // 4. traverse
    let counter = Counter()
    let t6 = MonoTime.now()
    for (_ in 0..iters) {
        counter.total = 0
        walk(preDoc) { kind =>
            match (kind) {
                case Element(el) =>
                    counter.total++
                    counter.total += el.attributeCount()
                    Continue
                case _ => Continue
            }
        }
        sink += counter.total
    }
    let t7 = MonoTime.now()
    emit(out, localFirst, "traverse", e.file, iters, durationMs(t7 - t6), bytes)

    // 用一下 sink 防 DCE：写到 stderr 上，正常基准模式不读 stderr
    if (sink == 0xDEADBEEF) {
        println("[unreachable] sink=${sink}")
    }
}

class Counter {
    public var total: Int64 = 0
}

func emit(out: StringBuilder, isFirst: Bool, scenario: String, fixture: String,
          iters: Int64, totalMs: Float64, bytes: Int64): Unit {
    if (!isFirst) { out.append(",\n") }
    let avg = totalMs / Float64(iters)
    out.append("    {\n")
    out.append("      \"scenario\": \"${scenario}\",\n")
    out.append("      \"fixture\": \"${fixture}\",\n")
    out.append("      \"iterations\": ${iters},\n")
    out.append("      \"elapsed_ms_total\": ${totalMs},\n")
    out.append("      \"elapsed_ms_avg\": ${avg},\n")
    out.append("      \"bytes\": ${bytes}\n")
    out.append("    }")
}

func durationMs(d: Duration): Float64 {
    Float64(d.toNanoseconds()) / 1_000_000.0
}

// ---- 字符串工具 -----------------------------------------------------------

func indexOf(s: String, needle: String, start: Int64): Int64 {
    let n = s.size
    let m = needle.size
    if (m == 0) { return start }
    var i = start
    while (i + m <= n) {
        var ok = true
        var j = 0
        while (j < m) {
            if (s[i + j] != needle[j]) { ok = false; break }
            j++
        }
        if (ok) { return i }
        i++
    }
    -1
}

// 注意：本工具是 perf bench 的"miniature JSON reader"，仅用于解析本进程
// 写出的 plan.json（内容是 ASCII，键名 `file` / `iterations`，无 Unicode）。
// 因此把 ASCII Rune 直接窄化为字节是安全的——超出 ASCII 范围的 Rune 会
// 被截断，但本场景下根本不会传入。命名上加 Ascii 后缀以提醒边界。
func indexOfAsciiChar(s: String, c: Rune, start: Int64): Int64 {
    let b = UInt8(UInt32(c))
    var i = start
    while (i < s.size) {
        if (s[i] == b) { return i }
        i++
    }
    -1
}

// JSON 值结束符（ASCII）的字节常量——预先求值，避免在热路径里
// 重复做 Rune→UInt32→UInt8 转换。
const DELIM_COMMA: Byte = 0x2Cu8 // ','
const DELIM_RBRACE: Byte = 0x7Du8 // '}'
const DELIM_LF: Byte = 0x0Au8 // '\n'
const DELIM_RBRACKET: Byte = 0x5Du8 // ']'

func isDelim(b: Byte): Bool {
    b == DELIM_COMMA || b == DELIM_RBRACE || b == DELIM_LF || b == DELIM_RBRACKET
}

func parseInt64(s: String): Int64 {
    var v: Int64 = 0
    var i = 0
    while (i < s.size) {
        let b = s[i]
        if (b >= UInt8(UInt32(r'0')) && b <= UInt8(UInt32(r'9'))) {
            v = v * 10 + Int64(b - UInt8(UInt32(r'0')))
        }
        i++
    }
    v
}
