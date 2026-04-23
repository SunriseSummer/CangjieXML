package cangjie_xml.dom

import std.unittest.*
import std.unittest.testmacro.*
import cangjie_xml.error.*

// ====================================================================
// XmlElement 行为测试：子节点 / 属性 / 文本内容 / 遍历。
// ====================================================================

@Test
func testChildInsertionAndSiblingLinks(): Unit {
    let doc = XmlDocument()
    let root = doc.createElement("r")
    doc.appendChild(root)

    let a = doc.createElement("a")
    let b = doc.createElement("b")
    let c = doc.createElement("c")
    root.appendChild(a)
    root.appendChild(c)
    root.insertChildBefore(c, b) // a, b, c

    // 验证顺序
    var names = ""
    for (e in root.childElements()) {
        names += e.name
    }
    @Expect(names, "abc")

    // 兄弟导航
    match (a.nextSibling) {
        case Some(n) =>
            match (n.kind()) {
                case Element(e) => @Expect(e.name, "b")
                case _ => @Assert(false)
            }
        case None => @Assert(false)
    }
    match (c.previousSibling) {
        case Some(p) =>
            match (p.kind()) {
                case Element(e) => @Expect(e.name, "b")
                case _ => @Assert(false)
            }
        case None => @Assert(false)
    }

    // 父节点
    match (b.parent) {
        case Some(p) => @Assert(refEq(p, root))
        case None => @Assert(false)
    }
}

@Test
func testPrependChild(): Unit {
    let doc = XmlDocument()
    let root = doc.createElement("r")
    doc.appendChild(root)
    root.appendChild(doc.createElement("b"))
    root.prependChild(doc.createElement("a"))

    var names = ""
    for (e in root.childElements()) {
        names += e.name
    }
    @Expect(names, "ab")
}

@Test
func testRemoveChildAndRemoveSelf(): Unit {
    let doc = XmlDocument()
    let root = doc.createElement("r")
    doc.appendChild(root)
    let a = doc.createElement("a")
    let b = doc.createElement("b")
    let c = doc.createElement("c")
    root.appendChild(a)
    root.appendChild(b)
    root.appendChild(c)

    @Expect(root.removeChild(b), true)
    var names = ""
    for (e in root.childElements()) {
        names += e.name
    }
    @Expect(names, "ac")
    // b 已脱离
    match (b.parent) {
        case None => ()
        case Some(_) => @Assert(false)
    }
    @Expect(b.previousSibling.isSome(), false)
    @Expect(b.nextSibling.isSome(), false)

    // removeSelf on detached node returns false
    @Expect(b.removeSelf(), false)

    // removeSelf on c
    @Expect(c.removeSelf(), true)
    var names2 = ""
    for (e in root.childElements()) {
        names2 += e.name
    }
    @Expect(names2, "a")
}

@Test
func testMoveBetweenParents(): Unit {
    let doc = XmlDocument()
    let root = doc.createElement("r")
    doc.appendChild(root)
    let a = doc.createElement("a")
    let b = doc.createElement("b")
    root.appendChild(a)
    root.appendChild(b)
    // 将 b 移到 a 下
    a.appendChild(b)
    // root 现在只剩 a
    var names = ""
    for (e in root.childElements()) {
        names += e.name
    }
    @Expect(names, "a")
    // a 有一个孩子 b
    match (a.firstChildElement()) {
        case Some(x) => @Expect(x.name, "b")
        case None => @Assert(false)
    }
}

@Test
func testCycleInsertionForbidden(): Unit {
    let doc = XmlDocument()
    let root = doc.createElement("r")
    doc.appendChild(root)
    let child = doc.createElement("c")
    root.appendChild(child)
    var caught = false
    try {
        child.appendChild(root) // 成环
    } catch (_: XmlException) {
        caught = true
    }
    @Expect(caught, true)
}

@Test
func testCrossDocumentInsertionForbidden(): Unit {
    let d1 = XmlDocument()
    let d2 = XmlDocument()
    let r1 = d1.createElement("r")
    d1.appendChild(r1)
    let alien = d2.createElement("x")
    var caught = false
    try {
        r1.appendChild(alien)
    } catch (_: XmlException) {
        caught = true
    }
    @Expect(caught, true)
}

@Test
func testAttributeOrderAndOverwrite(): Unit {
    let doc = XmlDocument()
    let el = doc.createElement("e")
    el.setAttribute("x", "1")
    el.setAttribute("y", "2")
    el.setAttribute("z", "3")
    el.setAttribute("x", "X") // 覆盖，不改变顺序

    var names = ""
    var vals = ""
    for (a in el.attributes()) {
        names += a.name
        vals += a.value
    }
    @Expect(names, "xyz")
    @Expect(vals, "X23")

    @Expect(el.attributeCount(), 3)
    match (el.attribute("x")) {
        case Some(v) => @Expect(v, "X")
        case None => @Assert(false)
    }
    @Expect(el.hasAttribute("y"), true)
    @Expect(el.hasAttribute("y", value: Some("2")), true)
    @Expect(el.hasAttribute("y", value: Some("bad")), false)
    @Expect(el.hasAttribute("none"), false)

    @Expect(el.removeAttribute("y"), true)
    @Expect(el.removeAttribute("y"), false)
    @Expect(el.attributeCount(), 2)
    var names2 = ""
    for (a in el.attributes()) {
        names2 += a.name
    }
    @Expect(names2, "xz")
}

@Test
func testTextContent(): Unit {
    let doc = XmlDocument()
    let root = doc.createElement("r")
    doc.appendChild(root)
    let sub = doc.createElement("s")
    root.appendChild(doc.createText("hello "))
    root.appendChild(sub)
    sub.appendChild(doc.createText("world"))
    root.appendChild(doc.createText("!"))
    // 注释不计入 textContent
    root.appendChild(doc.createComment("ignored"))

    @Expect(root.textContent(), "hello world!")
}

@Test
func testSetTextContent(): Unit {
    let doc = XmlDocument()
    let root = doc.createElement("r")
    doc.appendChild(root)
    root.appendChild(doc.createElement("sub"))
    root.appendChild(doc.createText("old"))
    root.setTextContent("new")
    @Expect(root.textContent(), "new")
    // 应该只剩一个 XmlText 子节点
    var count = 0
    for (_ in root.childNodes()) {
        count++
    }
    @Expect(count, 1)
}

@Test
func testFirstChildElementByName(): Unit {
    let doc = XmlDocument()
    let root = doc.createElement("r")
    doc.appendChild(root)
    root.appendChild(doc.createComment("c"))
    root.appendChild(doc.createElement("a"))
    root.appendChild(doc.createElement("b"))
    match (root.firstChildElement()) {
        case Some(e) => @Expect(e.name, "a")
        case None => @Assert(false)
    }
    match (root.firstChildElement(name: Some("b"))) {
        case Some(e) => @Expect(e.name, "b")
        case None => @Assert(false)
    }
    match (root.firstChildElement(name: Some("z"))) {
        case None => ()
        case Some(_) => @Assert(false)
    }
}

@Test
func testChildElementsFilterByName(): Unit {
    let doc = XmlDocument()
    let root = doc.createElement("r")
    doc.appendChild(root)
    root.appendChild(doc.createElement("a"))
    root.appendChild(doc.createElement("b"))
    root.appendChild(doc.createElement("a"))
    var n = 0
    for (e in root.childElements(name: Some("a"))) {
        n++
        @Expect(e.name, "a")
    }
    @Expect(n, 2)
}
