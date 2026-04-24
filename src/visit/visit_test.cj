package cangjie_xml.visit

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*
import cangjie_xml.dom.*
import cangjie_xml.build.*

// ======================================================================
// 共享测试夹具
// ======================================================================

/*
 * 构造一棵典型的 XML 树，用于多数 walk/accept 测试。
 *
 * <?xml ... ?>
 * <!-- top comment -->
 * <catalog>
 *   <book id="1">SICP</book>
 *   <book id="2"><!-- note -->TAOCP</book>
 *   <meta>42</meta>
 * </catalog>
 */
func makeTree(): XmlDocument {
    XmlDocumentBuilder()
        .declaration()
        .comment("top comment")
        .root("catalog") { r =>
            r.element("book") { b =>
                b.attribute("id", "1").text("SICP")
            }
            r.element("book") { b =>
                b.attribute("id", "2").comment("note").text("TAOCP")
            }
            r.element("meta") { m => m.text("42") }
        }
        .build()
}

// ======================================================================
// walk 基础与控制信号
// ======================================================================

class Counter {
    public var n: Int64 = 0
    public func inc(): Unit { n++ }
}

@Test
func testWalkVisitsEveryNode(): Unit {
    let doc = makeTree()
    let c = Counter()
    walk(doc) { _ => c.inc(); Continue }
    // Document + Declaration + top-Comment + catalog + book1 + text "SICP"
    //  + book2 + inner-Comment + text "TAOCP" + meta + text "42" = 11
    @Expect(c.n, 11)
}

@Test
func testWalkPreOrder(): Unit {
    let doc = makeTree()
    let order = ArrayList<String>()
    walk(doc) { kind =>
        match (kind) {
            case Document(_)    => order.add("doc")
            case Element(e)     => order.add("el:${e.name}")
            case Text(t)        => order.add("txt:${t.value}")
            case Comment(c)     => order.add("cmt:${c.value}")
            case Declaration(_) => order.add("decl")
            case Unknown(_)     => order.add("unk")
        }
        Continue
    }
    @Expect(order[0], "doc")
    @Expect(order[1], "decl")
    @Expect(order[2], "cmt:top comment")
    @Expect(order[3], "el:catalog")
    @Expect(order[4], "el:book")
    @Expect(order[5], "txt:SICP")
}

@Test
func testWalkSkipChildren(): Unit {
    let doc = makeTree()
    let c = Counter()
    // 跳过 catalog 的子树
    walk(doc) { kind =>
        c.inc()
        match (kind) {
            case Element(e) where e.name == "catalog" => SkipChildren
            case _ => Continue
        }
    }
    // 跳过 catalog 的所有后代，仍然应看到：doc + decl + top-comment + catalog 本身 = 4
    @Expect(c.n, 4)
}

@Test
func testWalkStopAbortsImmediately(): Unit {
    let doc = makeTree()
    let seen = ArrayList<String>()
    walk(doc) { kind =>
        match (kind) {
            case Element(e) =>
                seen.add(e.name)
                if (e.name == "book") {
                    return Stop
                }
                Continue
            case _ => Continue
        }
    }
    // 停在第一个 book 上：catalog 先入栈，然后 book 触发 Stop
    @Expect(seen.size, 2)
    @Expect(seen[0], "catalog")
    @Expect(seen[1], "book")
}

@Test
func testWalkOnLeafSkipChildrenEqualsContinue(): Unit {
    let doc = XmlDocumentBuilder().root("r") { r => r.text("hi") }.build()
    let c = Counter()
    walk(doc) { _ => c.inc(); SkipChildren }
    // SkipChildren 在 Document 根上 → 不进入；仅 Document 自身被访问
    @Expect(c.n, 1)
}

@Test
func testWalkOnElementSubtree(): Unit {
    // walk 也可从内部元素开始，而不是整个文档
    let doc = makeTree()
    let root = doc.rootElement.getOrThrow()
    let c = Counter()
    walk(root) { _ => c.inc(); Continue }
    // catalog + 2*book + 2*text + 1 inner-comment + meta + 1 text = 8
    @Expect(c.n, 8)
}

// ======================================================================
// accept：XmlVisitor 的各分支
// ======================================================================

class CountingVisitor <: XmlVisitor {
    public var enteredDocs: Int64 = 0
    public var exitedDocs: Int64 = 0
    public var enteredEls: Int64 = 0
    public var exitedEls: Int64 = 0
    public var texts: Int64 = 0
    public var comments: Int64 = 0
    public var decls: Int64 = 0
    public var unknowns: Int64 = 0

    public func visitEnter(document: XmlDocument): Bool { enteredDocs++; true }
    public func visitExit(document: XmlDocument): Bool  { exitedDocs++; true }
    public func visitEnter(element: XmlElement): Bool   { enteredEls++; true }
    public func visitExit(element: XmlElement): Bool    { exitedEls++; true }
    public func visit(text: XmlText): Bool              { texts++; true }
    public func visit(comment: XmlComment): Bool        { comments++; true }
    public func visit(declaration: XmlDeclaration): Bool { decls++; true }
    public func visit(unknown: XmlUnknown): Bool         { unknowns++; true }
}

@Test
func testAcceptFullDispatch(): Unit {
    let doc = makeTree()
    let v = CountingVisitor()
    @Expect(accept(doc, v), true)
    @Expect(v.enteredDocs, 1)
    @Expect(v.exitedDocs, 1)
    @Expect(v.enteredEls, 4)  // catalog + book + book + meta
    @Expect(v.exitedEls, 4)
    @Expect(v.texts, 3)       // SICP, TAOCP, 42
    @Expect(v.comments, 2)    // top + inner
    @Expect(v.decls, 1)
    @Expect(v.unknowns, 0)
}

class PruneBookVisitor <: XmlVisitor {
    public var enteredEls: Int64 = 0
    public var exitedEls: Int64 = 0
    public var texts: Int64 = 0

    public func visitEnter(element: XmlElement): Bool {
        enteredEls++
        // 剪枝：不进入 <book> 子树
        return element.name != "book"
    }
    public func visitExit(element: XmlElement): Bool {
        exitedEls++
        true
    }
    public func visit(text: XmlText): Bool {
        texts++
        true
    }
}

@Test
func testAcceptVisitEnterFalseSkipsSubtreeAndExit(): Unit {
    let doc = makeTree()
    let v = PruneBookVisitor()
    @Expect(accept(doc, v), true)
    // visitEnter 被调 4 次（catalog + book + book + meta），visitExit 仅对未剪枝的调用
    @Expect(v.enteredEls, 4)
    // 剪掉 2 个 book，留下 catalog + meta 触发 exit
    @Expect(v.exitedEls, 2)
    // book 的文本被剪掉了，只剩 meta 的 "42"
    @Expect(v.texts, 1)
}

class StopOnTextVisitor <: XmlVisitor {
    public var texts: Int64 = 0
    public var elementExits: Int64 = 0

    public func visit(text: XmlText): Bool {
        texts++
        // 看到第一段文本就停止
        false
    }

    public func visitExit(element: XmlElement): Bool {
        elementExits++
        true
    }
}

@Test
func testAcceptLeafFalsePropagates(): Unit {
    let doc = makeTree()
    let v = StopOnTextVisitor()
    // 叶子 visit 返回 false → accept 总体返回 false
    @Expect(accept(doc, v), false)
    @Expect(v.texts, 1)
    // 被中断的路径上的 visitExit 依然应被调用（RAII 对称）
    // catalog → book (exit) 和 catalog 本身 (exit) 都应触发
    @Expect(v.elementExits >= 2, true)
}

// ======================================================================
// XmlVisitable 扩展方法
// ======================================================================

@Test
func testXmlVisitableAcceptMethod(): Unit {
    let doc = makeTree()
    let v = CountingVisitor()
    @Expect(doc.accept(v), true)
    @Expect(v.enteredDocs, 1)
    @Expect(v.enteredEls, 4)
}

@Test
func testXmlVisitableWalkMethod(): Unit {
    let doc = makeTree()
    let c = Counter()
    doc.walk { _ => c.inc(); Continue }
    @Expect(c.n, 11)
}

// ======================================================================
// 与 query / build 联动
// ======================================================================

@Test
func testCollectElementsByNameViaWalk(): Unit {
    let doc = makeTree()
    let books = ArrayList<XmlElement>()
    walk(doc) { kind =>
        match (kind) {
            case Element(e) where e.name == "book" =>
                books.add(e)
                SkipChildren  // 不再进入 book 的子树
            case _ => Continue
        }
    }
    @Expect(books.size, 2)
    @Expect(books[0].attribute("id").getOrThrow(), "1")
    @Expect(books[1].attribute("id").getOrThrow(), "2")
}

@Test
func testEmptyElementHasNoChildrenWalked(): Unit {
    let doc = XmlDocumentBuilder().root("empty").build()
    let c = Counter()
    walk(doc) { _ => c.inc(); Continue }
    // Document + empty root = 2
    @Expect(c.n, 2)
}
