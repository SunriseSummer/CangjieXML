/*
 * tree — Element 变更 API 单元测试（Phase 4b · 属性 / detach / 不变量 / 端到端）
 *
 * 与 `element_mutation_test.cj` 配套；共享 helper 在那里定义。
 */
package cangjie_xml.tree

import std.unittest.*
import cangjie_xml.core.*
import cangjie_xml.parser.*

/* ---------- 属性变更 ---------- */

@Test
public func testSetAttributeAddsNew(): Unit {
    let root = mkElem("root")
    root.setAttribute(QName("id"), "1")
    root.setAttribute(QName("class"), "x")
    @Expect(root.attributeCount(), 2)
    @Expect(root.findAttribute("id").getOrThrow().value, "1")
}

@Test
public func testSetAttributeReplacesExisting(): Unit {
    let root = mkElem("root")
    root.setAttribute(QName("id"), "1")
    root.setAttribute(QName("id"), "2")
    @Expect(root.attributeCount(), 1)
    @Expect(root.findAttribute("id").getOrThrow().value, "2")
}

@Test
public func testSetAttributeWithPrefixDoesNotDup(): Unit {
    // 前缀不参与匹配：(localName, uri) 相同即视为同一属性。
    let root = mkElem("root")
    root.setAttribute(QName("id", prefix: Some("a"), uri: Some("urn:x")), "1")
    root.setAttribute(QName("id", prefix: Some("b"), uri: Some("urn:x")), "2")
    @Expect(root.attributeCount(), 1)
    @Expect(root.findAttribute("id", uri: Some("urn:x")).getOrThrow().value, "2")
}

@Test
public func testRemoveAttribute(): Unit {
    let root = mkElem("root")
    root.setAttribute(QName("id"), "1")
    @Expect(root.removeAttribute("id"), true)
    @Expect(root.attributeCount(), 0)
    @Expect(root.removeAttribute("id"), false)
}

@Test
public func testClearAttributes(): Unit {
    let root = mkElem("root")
    root.setAttribute(QName("id"), "1")
    root.setAttribute(QName("class"), "x")
    root.clearAttributes()
    @Expect(root.attributeCount(), 0)
}

/* ---------- detach ---------- */

@Test
public func testDetachElement(): Unit {
    let root = mkElem("root")
    let a = mkElem("a")
    root.appendChild(a)
    a.detach()
    @Expect(root.childCount(), 0)
    @Expect(a.parent().isNone(), true)
    // 再次 detach 无副作用
    a.detach()
}

@Test
public func testDetachLeafTypes(): Unit {
    let root = mkElem("root")
    let t = mkText("x")
    let c = mkCdata("y")
    let cm = mkComment("z")
    let pi = mkPi("p", "d")
    root.appendChild(t)
    root.appendChild(c)
    root.appendChild(cm)
    root.appendChild(pi)
    @Expect(root.childCount(), 4)
    t.detach()
    c.detach()
    cm.detach()
    pi.detach()
    @Expect(root.childCount(), 0)
}

/* ---------- 不变量校验 ---------- */

@Test
public func testCannotInsertSelf(): Unit {
    let root = mkElem("root")
    var threw = false
    try {
        root.appendChild(root)
    } catch (_: XmlException) {
        threw = true
    }
    @Expect(threw, true)
}

@Test
public func testCannotInsertAncestor(): Unit {
    let root = mkElem("root")
    let child = mkElem("c")
    root.appendChild(child)
    var threw = false
    try {
        child.appendChild(root) // 会成环
    } catch (_: XmlException) {
        threw = true
    }
    @Expect(threw, true)
    // 原有结构不破坏
    @Expect(root.childCount(), 1)
    @Expect(refEq(child.parent().getOrThrow(), root), true)
}

@Test
public func testCannotInsertDoctypeIntoElement(): Unit {
    let root = mkElem("root")
    let dt = DoctypeNode("html")
    var threw = false
    try {
        root.appendChild(dt)
    } catch (_: XmlException) {
        threw = true
    }
    @Expect(threw, true)
}

/* ---------- 端到端：parse → 修改 ---------- */

@Test
public func testEndToEndMutationRoundtrip(): Unit {
    let doc = DocumentBuilder.parseString("<root><a/><c/></root>")
    let root = doc.root
    // 找到 a 和 c
    var aElem: ?Element = None
    var cElem: ?Element = None
    for (n in root.children()) {
        match (n) {
            case e: Element where e.qname.localName == "a" => aElem = Some(e)
            case e: Element where e.qname.localName == "c" => cElem = Some(e)
            case _ => ()
        }
    }
    // 在 a 和 c 之间插入 b
    let b = mkElem("b")
    root.insertBefore(b, cElem.getOrThrow())
    // 删除 a
    root.removeChild(aElem.getOrThrow())
    // 给 c 加一个属性
    cElem.getOrThrow().setAttribute(QName("k"), "v")
    // 校验结构
    @Expect(root.childCount(), 2)
    @Expect(root.childAt(0).nodeKind() == NodeKind.ElementNode, true)
    match (root.childAt(0)) {
        case e: Element => @Expect(e.qname.localName, "b")
        case _ => @Fail("expected Element")
    }
    match (root.childAt(1)) {
        case e: Element =>
            @Expect(e.qname.localName, "c")
            @Expect(e.findAttribute("k").getOrThrow().value, "v")
        case _ => @Fail("expected Element")
    }
}

@Test
public func testMoveBetweenTreesAcrossDocuments(): Unit {
    // 跨 DOM 移动：一个 Element 从树 A 脱离，挂到树 B 上。
    let docA = DocumentBuilder.parseString("<a><x>hi</x></a>")
    let docB = DocumentBuilder.parseString("<b/>")
    // 取出 docA.root 的第一个子（<x>）
    var xElem: ?Element = None
    for (n in docA.root.children()) {
        match (n) {
            case e: Element => xElem = Some(e)
            case _ => ()
        }
    }
    let x = xElem.getOrThrow()
    docB.root.appendChild(x)
    @Expect(docA.root.childCount(), 0)
    @Expect(docB.root.childCount(), 1)
    @Expect(refEq(x.parent().getOrThrow(), docB.root), true)
    @Expect(docB.root.allText(), "hi")
}

/* ---------- hasChild / indexOfChild ---------- */

@Test
public func testHasChildAndIndexOfChild(): Unit {
    let root = mkElem("root")
    let a = mkElem("a")
    let stranger = mkElem("s")
    root.appendChild(a)
    @Expect(root.hasChild(a), true)
    @Expect(root.hasChild(stranger), false)
    @Expect(root.indexOfChild(a), 0)
    @Expect(root.indexOfChild(stranger), -1)
}
