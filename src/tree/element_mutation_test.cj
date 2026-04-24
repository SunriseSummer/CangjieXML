/*
 * tree — Element 变更 API 单元测试（Phase 4b）
 *
 * 覆盖：
 *   - appendChild / prependChild / insertBefore / insertAfter
 *   - removeChild / removeChildAt / clearChildren
 *   - replaceChild
 *   - setAttribute / removeAttribute / clearAttributes
 *   - detach（Element + 各叶子类型）
 *   - indexOfChild / hasChild
 *   - 不变量：自动 detach、无环、拒绝 Document / Doctype、拒绝非子引用
 *   - 与 DocumentBuilder / DocumentSerializer 的端到端往返
 */
package cangjie_xml.tree

import std.unittest.*
import cangjie_xml.core.*
import cangjie_xml.parser.*

/* ---------- 本文件共享的构造辅助 ---------- */

func mkElem(name: String): Element {
    return Element(QName(name), NsContext.root())
}

func mkText(s: String): TextNode {
    return TextNode(s)
}

func mkComment(s: String): CommentNode {
    return CommentNode(s)
}

func mkPi(t: String, d: String): PiNode {
    return PiNode(t, d)
}

func mkCdata(s: String): CdataSection {
    return CdataSection(s)
}

/* ---------- appendChild / prependChild ---------- */

@Test
public func testAppendChildBasic(): Unit {
    let root = mkElem("root")
    let a = mkElem("a")
    let b = mkElem("b")
    root.appendChild(a)
    root.appendChild(b)
    @Expect(root.childCount(), 2)
    @Expect(a.parent().getOrThrow().qname.localName, "root")
    @Expect(b.parent().getOrThrow().qname.localName, "root")
    @Expect(root.childAt(0).nodeKind() == NodeKind.ElementNode, true)
}

@Test
public func testAppendChildTextNode(): Unit {
    let root = mkElem("root")
    let t = mkText("hi")
    root.appendChild(t)
    @Expect(root.childCount(), 1)
    @Expect(t.parent().isSome(), true)
    @Expect(root.directText(), "hi")
}

@Test
public func testPrependChild(): Unit {
    let root = mkElem("root")
    let a = mkElem("a")
    let b = mkElem("b")
    root.appendChild(a)
    root.prependChild(b)
    @Expect(root.indexOfChild(b), 0)
    @Expect(root.indexOfChild(a), 1)
}

@Test
public func testAppendAutoDetachesFromOldParent(): Unit {
    let p1 = mkElem("p1")
    let p2 = mkElem("p2")
    let child = mkElem("c")
    p1.appendChild(child)
    @Expect(p1.childCount(), 1)
    p2.appendChild(child)
    @Expect(p1.childCount(), 0)
    @Expect(p2.childCount(), 1)
    @Expect(refEq(child.parent().getOrThrow(), p2), true)
}

/* ---------- insertBefore / insertAfter ---------- */

@Test
public func testInsertBefore(): Unit {
    let root = mkElem("root")
    let a = mkElem("a")
    let b = mkElem("b")
    let c = mkElem("c")
    root.appendChild(a)
    root.appendChild(c)
    root.insertBefore(b, c)
    @Expect(root.indexOfChild(a), 0)
    @Expect(root.indexOfChild(b), 1)
    @Expect(root.indexOfChild(c), 2)
}

@Test
public func testInsertAfter(): Unit {
    let root = mkElem("root")
    let a = mkElem("a")
    let b = mkElem("b")
    let c = mkElem("c")
    root.appendChild(a)
    root.appendChild(c)
    root.insertAfter(b, a)
    @Expect(root.indexOfChild(a), 0)
    @Expect(root.indexOfChild(b), 1)
    @Expect(root.indexOfChild(c), 2)
}

@Test
public func testInsertBeforeSelfIsNoop(): Unit {
    let root = mkElem("root")
    let a = mkElem("a")
    root.appendChild(a)
    root.insertBefore(a, a)
    @Expect(root.childCount(), 1)
    @Expect(root.indexOfChild(a), 0)
}

@Test
public func testInsertBeforeFailsForNonChildReference(): Unit {
    let root = mkElem("root")
    let a = mkElem("a")
    let other = mkElem("other")
    let newNode = mkElem("n")
    root.appendChild(a)
    var threw = false
    try {
        root.insertBefore(newNode, other)
    } catch (_: XmlException) {
        threw = true
    }
    @Expect(threw, true)
    @Expect(root.childCount(), 1)
    @Expect(newNode.parent().isNone(), true)
}

@Test
public func testInsertBeforeMovesSibling(): Unit {
    // 把本元素内部的 a 移到 c 前面 —— 自动 detach 后重插不应错位。
    let root = mkElem("root")
    let a = mkElem("a")
    let b = mkElem("b")
    let c = mkElem("c")
    root.appendChild(a)
    root.appendChild(b)
    root.appendChild(c)
    root.insertBefore(a, c)
    @Expect(root.indexOfChild(b), 0)
    @Expect(root.indexOfChild(a), 1)
    @Expect(root.indexOfChild(c), 2)
}

/* ---------- removeChild / removeChildAt / clearChildren ---------- */

@Test
public func testRemoveChild(): Unit {
    let root = mkElem("root")
    let a = mkElem("a")
    let b = mkElem("b")
    root.appendChild(a)
    root.appendChild(b)
    @Expect(root.removeChild(a), true)
    @Expect(root.childCount(), 1)
    @Expect(a.parent().isNone(), true)
    @Expect(root.removeChild(a), false) // 再次移除：false
}

@Test
public func testRemoveChildAt(): Unit {
    let root = mkElem("root")
    let a = mkElem("a")
    let b = mkElem("b")
    root.appendChild(a)
    root.appendChild(b)
    let got = root.removeChildAt(0)
    @Expect(refEq(got as Element ?? mkElem("?"), a), true)
    @Expect(root.childCount(), 1)
}

@Test
public func testClearChildren(): Unit {
    let root = mkElem("root")
    let a = mkElem("a")
    let b = mkElem("b")
    root.appendChild(a)
    root.appendChild(b)
    root.clearChildren()
    @Expect(root.childCount(), 0)
    @Expect(a.parent().isNone(), true)
    @Expect(b.parent().isNone(), true)
}

@Test
public func testRemoveNonChildReturnsFalse(): Unit {
    let root = mkElem("root")
    let stranger = mkElem("x")
    @Expect(root.removeChild(stranger), false)
}

/* ---------- replaceChild ---------- */

@Test
public func testReplaceChild(): Unit {
    let root = mkElem("root")
    let a = mkElem("a")
    let b = mkElem("b")
    let c = mkElem("c")
    root.appendChild(a)
    root.appendChild(b)
    root.replaceChild(b, c)
    @Expect(root.indexOfChild(a), 0)
    @Expect(root.indexOfChild(c), 1)
    @Expect(root.indexOfChild(b), -1)
    @Expect(b.parent().isNone(), true)
    @Expect(refEq(c.parent().getOrThrow(), root), true)
}

@Test
public func testReplaceChildSameNodeIsNoop(): Unit {
    let root = mkElem("root")
    let a = mkElem("a")
    root.appendChild(a)
    root.replaceChild(a, a)
    @Expect(root.childCount(), 1)
}

@Test
public func testReplaceChildFailsForNonChild(): Unit {
    let root = mkElem("root")
    let a = mkElem("a")
    let stranger = mkElem("s")
    let newNode = mkElem("n")
    root.appendChild(a)
    var threw = false
    try {
        root.replaceChild(stranger, newNode)
    } catch (_: XmlException) {
        threw = true
    }
    @Expect(threw, true)
}
