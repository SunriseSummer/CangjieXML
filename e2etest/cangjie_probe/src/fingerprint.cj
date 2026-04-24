package cangjie_probe

import std.collection.*
import std.fs.*
import std.sort.*
import cangjie_xml.dom.*
import cangjie_xml.io.*
import cangjie_xml.parser.*
import cangjie_xml.writer.*

/** Probe 的五种运行模式——影响 `loadForFingerprint` 走哪条库路径。 */
enum ProbeMode {
    | ModeParse
    | ModeRoundTripPretty
    | ModeRoundTripCompact
    | ModeBytesRoundTrip
    | ModeBuilder
}

/**
 * 把单个 fixture 的指纹写进 `out`。JSON 形状与 `python_probe/probe.py` 完全一致
 * ——两端任何字段顺序 / 键名 / 文本规范化规则的偏差都会被 diff 立刻炸出。
 */
func writeFileFingerprint(out: StringBuilder, dir: String, name: String, mode: ProbeMode): Unit {
    let path = "${dir}/${name}"
    let doc = loadDocForMode(path, mode)

    let elements = ArrayList<ElementRecord>()
    match (doc.rootElement) {
        case Some(root) => visitElement(root, "", 0, 0, elements)
        case None => ()
    }

    // `declaration_present` 永远按原始字节判定；roundtrip 写出的 XML 即便丢了
    // declaration（compact + writeDeclaration=true 保留；pretty 默认也保留），
    // 也不应改变"原文件指纹"的该字段——否则 diff 反而会误报。
    let declPresent = hasXmlDeclaration(path)
    let rootName = match (doc.rootElement) {
        case Some(r) => r.name
        case None => ""
    }

    emitFingerprint(out, name, declPresent, rootName, elements)
}

/** 根据模式选择库路径：直接 parse / parse→write→parse 的往返。 */
func loadDocForMode(path: String, mode: ProbeMode): XmlDocument {
    match (mode) {
        case ModeParse => loadXmlFromFile(path)
        case ModeRoundTripPretty => roundTrip(loadXmlFromFile(path), XmlWriteOptions.default_())
        case ModeRoundTripCompact => roundTrip(loadXmlFromFile(path), XmlWriteOptions.compactPreset())
        case ModeBytesRoundTrip =>
            // 走 bytes 专用 API：parseXmlBytes → writeXmlToBytes → parseXmlBytes。
            // 和 `roundtrip-*` 的区别在于两端都用字节 API——覆盖 io 包里从
            // `Array<Byte>` 进出的路径（HTTP / DB / 嵌入资源场景）。
            let raw = File.readFrom(Path(path))
            let parsed = parseXmlBytes(raw)
            let serialized = writeXmlToBytes(parsed, XmlWriteOptions.compactPreset())
            parseXmlBytes(serialized)
        case ModeBuilder =>
            // `builder` 模式不应通过本函数——由 `renderBuilderFixtures` 直接调用。
            throw Exception("loadDocForMode called with ModeBuilder (internal error)")
    }
}

/** parse → write（以 `opts` 排版）→ parse，返回新 Document。 */
func roundTrip(doc: XmlDocument, opts: XmlWriteOptions): XmlDocument {
    let sink = StringXmlSink()
    let w = XmlWriter(sink, options: opts)
    w.writeDocument(doc)
    parseXml(sink.toString())
}

/** 写出一条 fixture 的指纹 JSON。抽取以便 `renderBuilderFixtures` 复用。 */
func emitFingerprint(
    out: StringBuilder, name: String,
    declPresent: Bool, rootName: String,
    elements: ArrayList<ElementRecord>
): Unit {
    out.append("  \"${jsonEscape(name)}\": {\n")
    out.append("    \"file\": \"${jsonEscape(name)}\",\n")
    out.append("    \"declaration_present\": ${declPresent},\n")
    out.append("    \"root\": \"${jsonEscape(rootName)}\",\n")
    out.append("    \"total_elements\": ${elements.size},\n")
    out.append("    \"elements\": [")
    var firstEl = true
    for (rec in elements) {
        if (!firstEl) { out.append(",") }
        firstEl = false
        out.append("\n      ")
        writeElementRecord(out, rec)
    }
    if (!firstEl) { out.append("\n    ") }
    out.append("]\n")
    out.append("  }")
}

/** 用 record 持有单个元素的指纹字段——让"收集"与"序列化"解耦。 */
class ElementRecord {
    public let path: String
    public let depth: Int64
    public let name: String
    /** 按属性名字典序排好的 (name, value) 对。 */
    public let attrs: ArrayList<(String, String)>
    public let text: String
    public init(
        path: String, depth: Int64, name: String,
        attrs: ArrayList<(String, String)>, text: String
    ) {
        this.path = path
        this.depth = depth
        this.name = name
        this.attrs = attrs
        this.text = text
    }
}

func writeElementRecord(out: StringBuilder, r: ElementRecord): Unit {
    out.append("{\"path\": \"${jsonEscape(r.path)}\", \"depth\": ${r.depth}, ")
    out.append("\"name\": \"${jsonEscape(r.name)}\", \"attrs\": {")
    var firstA = true
    for ((k, v) in r.attrs) {
        if (!firstA) { out.append(", ") }
        firstA = false
        out.append("\"${jsonEscape(k)}\": \"${jsonEscape(v)}\"")
    }
    out.append("}, \"text\": \"${jsonEscape(r.text)}\"}")
}

/**
 * 与 Python 侧 `visit` 严格对齐：对每个元素按"同名兄弟序号"生成 `path`，
 * 并把自身记录追加到扁平列表，再递归孩子。
 */
func visitElement(
    el: XmlElement, parentPath: String,
    depth: Int64, siblingIndex: Int64,
    out: ArrayList<ElementRecord>
): Unit {
    let segment = "${el.name}[${siblingIndex}]"
    let path = if (parentPath.isEmpty()) { segment } else { "${parentPath}/${segment}" }

    out.add(ElementRecord(
        path, depth, el.name,
        collectSortedAttrs(el),
        directText(el),
    ))

    // 孩子按 name 维护同名兄弟序号
    let counters = HashMap<String, Int64>()
    for (child in el.childNodes()) {
        match (child.kind()) {
            case Element(c) =>
                let idx = counters.get(c.name) ?? 0
                counters[c.name] = idx + 1
                visitElement(c, path, depth + 1, idx, out)
            case _ => ()
        }
    }
}

/** 读取 el 的直接文本：仅该元素下的 XmlText 子节点（含 CDATA），规范化后拼接。 */
func directText(el: XmlElement): String {
    let buf = StringBuilder()
    for (child in el.childNodes()) {
        match (child.kind()) {
            case Text(t) => buf.append(t.value)
            case _ => ()
        }
    }
    normalizeWhitespace(buf.toString())
}

/** 与 Python 侧的 `normalize_text` 等价：内部连续空白折叠为单空格，两端 strip。
 *
 *  实现要点：按**字节**扫描，但非空白字节原样复制到输出（不经过 `Rune`）。
 *  否则 `Rune(UInt32(b))` 会把每个 UTF-8 续字节当成独立码点，中文 / emoji
 *  会被拆散再重组为伪 Latin-1 字符串，导致与 Python 侧 diff 不上。
 */
func normalizeWhitespace(s: String): String {
    let bytes = s.toArray()
    let out = ArrayList<Byte>()
    var prevSpace = false
    for (b in bytes) {
        let isSpace = b == b' ' || b == b'\t' || b == b'\n' || b == b'\r'
        if (isSpace) {
            if (!prevSpace) { out.add(b' ') }
            prevSpace = true
        } else {
            out.add(b)
            prevSpace = false
        }
    }
    // strip 两端空格
    var lo = 0
    var hi = out.size
    while (lo < hi && out[lo] == b' ') { lo += 1 }
    while (hi > lo && out[hi - 1] == b' ') { hi -= 1 }
    let sliced = Array<Byte>(hi - lo, repeat: 0)
    for (i in 0..sliced.size) { sliced[i] = out[lo + i] }
    String.fromUtf8(sliced)
}

func collectSortedAttrs(el: XmlElement): ArrayList<(String, String)> {
    let pairs = ArrayList<(String, String)>()
    for (a in el.attributes()) { pairs.add((a.name, a.value)) }
    sort<(String, String)>(pairs, by: { l: (String, String), r: (String, String) =>
        if (l[0] < r[0]) { Ordering.LT }
        else if (l[0] > r[0]) { Ordering.GT }
        else { Ordering.EQ }
    })
    pairs
}

/** 通过读取文件头 64 字节来判断是否存在 `<?xml` 声明，容忍 BOM。 */
func hasXmlDeclaration(path: String): Bool {
    let bytes = File.readFrom(Path(path))
    var start = 0
    if (bytes.size >= 3 && bytes[0] == 0xEFu8 && bytes[1] == 0xBBu8 && bytes[2] == 0xBFu8) {
        start = 3
    }
    // skip leading whitespace
    while (start < bytes.size) {
        let b = bytes[start]
        if (b == b' ' || b == b'\t' || b == b'\n' || b == b'\r') { start += 1 }
        else { break }
    }
    let needle: Array<Byte> = [b'<', b'?', b'x', b'm', b'l']
    if (start + needle.size > bytes.size) { return false }
    for (i in 0..needle.size) {
        if (bytes[start + i] != needle[i]) { return false }
    }
    true
}

/** JSON 字符串转义——只处理必须转义的 ASCII 控制字符；其它 UTF-8 字节原样复制。
 *
 *  与 `normalizeWhitespace` 同理：非特殊字节绝不走 `Rune` 构造，否则会把 UTF-8
 *  续字节当独立码点、重新编码成乱码。
 */
func jsonEscape(s: String): String {
    let bytes = s.toArray()
    let out = ArrayList<Byte>()
    for (b in bytes) {
        if (b == b'\\') { appendAscii(out, "\\\\") }
        else if (b == b'"') { appendAscii(out, "\\\"") }
        else if (b == b'\n') { appendAscii(out, "\\n") }
        else if (b == b'\r') { appendAscii(out, "\\r") }
        else if (b == b'\t') { appendAscii(out, "\\t") }
        else if (b < 0x20u8) {
            appendAscii(out, "\\u00")
            appendAscii(out, hexNibble(Int64(b) / 16))
            appendAscii(out, hexNibble(Int64(b) % 16))
        }
        else { out.add(b) }
    }
    let arr = Array<Byte>(out.size, repeat: 0)
    for (i in 0..arr.size) { arr[i] = out[i] }
    String.fromUtf8(arr)
}

func appendAscii(out: ArrayList<Byte>, s: String): Unit {
    for (b in s.toArray()) { out.add(b) }
}

func hexNibble(n: Int64): String {
    if (n < 10) { "${n}" }
    else { String(Rune(UInt32(87 + n))) }  // 'a' = 97 → 97 - 10 = 87
}

