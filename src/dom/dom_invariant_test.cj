package cangjie_xml.dom

import std.unittest.*
import std.unittest.testmacro.*
import cangjie_xml.error.*

// =====================================================================
// DOM 不变量回归测试：
// 1. 属性名不可就地修改（`XmlAttribute.name` 为 `let`）；
// 2. `XmlDeclaration` 必须是文档首个顶层节点；
// 3. 插非 Declaration 到首个 Declaration 之前被拒绝。
//
// 这三条对应 DESIGN 与各自源码里注释过、但曾经未强制的契约。
// =====================================================================

@Test
func testAttributeNameIsImmutable(): Unit {
    // 本测试存在的意义是"锁死编译期契约"——若未来有人把 `name` 改回 `var`，
    // 这里就无需断言什么，编译期另一个修正就会失败。我们反向验证：创建后
    // 再通过 setAttribute 改名，老名不可再索引到值。
    let doc = XmlDocument()
    let el = doc.createElement("x")
    el.setAttribute("id", "1")
    // 用户正确的改名路径：remove + set。
    el.removeAttribute("id")
    el.setAttribute("ident", "1")
    @Expect(el.attribute("id").isNone(), true)
    @Expect(el.attribute("ident") ?? "", "1")
    // 属性顺序仍被维护（只剩新名）。
    let names: Array<String> = collectAttrNames(el)
    @Expect(names.size, 1)
    @Expect(names[0], "ident")
}

@Test
func testAppendDeclarationRequiresEmptyDocument(): Unit {
    // 在有非 decl 节点后 appendChild(decl) 必须抛。
    let doc = XmlDocument()
    doc.appendChild(doc.createComment("hi"))
    var threw = false
    try {
        doc.appendChild(doc.createDeclaration())
    } catch (_: XmlException) {
        threw = true
    }
    @Expect(threw, true)
}

@Test
func testPrependDeclarationIntoNonEmptyDocumentAllowed(): Unit {
    // 反向：prependChild(decl) 是合法的——它会成为新的 head。
    let doc = XmlDocument()
    doc.appendChild(doc.createComment("hi"))
    doc.prependChild(doc.createDeclaration())
    @Expect(doc.declaration.isSome(), true)
    // 验证顺序：decl 在前，comment 在后。
    var kinds: Array<String> = collectTopLevelKindNames(doc)
    @Expect(kinds[0], "Declaration")
    @Expect(kinds[1], "Comment")
}

@Test
func testCannotPrependBeforeDeclaration(): Unit {
    // 已存在 decl 作为 head 时，任何非 decl 的 prepend 都要被拒。
    let doc = XmlDocument()
    doc.appendChild(doc.createDeclaration())
    var threw = false
    try {
        doc.prependChild(doc.createComment("leading"))
    } catch (_: XmlException) {
        threw = true
    }
    @Expect(threw, true)
    // Declaration 仍是首节点。
    let kinds = collectTopLevelKindNames(doc)
    @Expect(kinds[0], "Declaration")
    @Expect(kinds.size, 1)
}

@Test
func testAppendCommentAfterDeclarationAllowed(): Unit {
    // 常规合法路径：先 decl 再 comment 再 root。
    let doc = XmlDocument()
    doc.appendChild(doc.createDeclaration())
    doc.appendChild(doc.createComment("c"))
    doc.appendChild(doc.createElement("r"))
    let kinds = collectTopLevelKindNames(doc)
    @Expect(kinds.size, 3)
    @Expect(kinds[0], "Declaration")
    @Expect(kinds[1], "Comment")
    @Expect(kinds[2], "Element")
}

// --- 小工具 -----------------------------------------------------------

func collectAttrNames(el: XmlElement): Array<String> {
    let out = ArrayOf<String>()
    for (a in el.attributes()) { out.add(a.name) }
    out.toArr()
}

func collectTopLevelKindNames(doc: XmlDocument): Array<String> {
    let out = ArrayOf<String>()
    for (n in doc.childNodes()) {
        out.add(match (n.kind()) {
            case Element(_)     => "Element"
            case Text(_)        => "Text"
            case Comment(_)     => "Comment"
            case Declaration(_) => "Declaration"
            case Unknown(_)     => "Unknown"
            case Document(_)    => "Document"
        })
    }
    out.toArr()
}

/**
 * 本测试自用的"只追加不预知大小"的小容器——`Array<String>(n, repeat: "")`
 * 要求先算总数，`ArrayList` 又要 import 成本；保持测试文件极简。
 */
class ArrayOf<T> {
    private var buf: Array<T> = Array<T>()
    public func add(v: T): Unit {
        let n = buf.size
        let g = Array<T>(n + 1, { i => if (i < n) { buf[i] } else { v } })
        buf = g
    }
    public func toArr(): Array<T> { buf }
}
