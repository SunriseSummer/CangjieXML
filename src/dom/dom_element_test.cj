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

// ====================================================================
// 覆盖率补充：XmlNode equals/notEquals、element children 边界、
// element firstChild/lastChild、isEmpty、跨文档、类型约束。
// ====================================================================

@Test
func testXmlNodeIdentityOperators(): Unit {
    let doc = XmlDocument()
    let a = doc.createElement("a")
    let b = doc.createElement("a")
    @Expect(a == a, true)
    @Expect(a != b, true)
    @Expect(a == b, false)
    @Expect(a != a, false)
}

@Test
func testXmlElementFirstLastChildAndIsEmpty(): Unit {
    let doc = XmlDocument()
    let r = doc.createElement("r")
    doc.appendChild(r)
    @Expect(r.isEmpty(), true)
    @Expect(r.firstChild.isNone(), true)
    @Expect(r.lastChild.isNone(), true)

    let a = doc.createElement("a")
    let b = doc.createElement("b")
    r.appendChild(a)
    r.appendChild(b)
    @Expect(r.isEmpty(), false)
    match (r.firstChild) {
        case Some(n) => @Assert(refEq(n, a))
        case None => @Fail("firstChild missing")
    }
    match (r.lastChild) {
        case Some(n) => @Assert(refEq(n, b))
        case None => @Fail("lastChild missing")
    }
}

@Test
func testPrependChildOnEmptyElementEquivalentToAppend(): Unit {
    // 覆盖 prependChild 的 `headChild == None` 分支。
    let doc = XmlDocument()
    let r = doc.createElement("r")
    doc.appendChild(r)
    let c = doc.createElement("c")
    r.prependChild(c)
    @Expect(r.firstChildElement().getOrThrow().name, "c")
}

@Test
func testInsertChildBeforeReferenceMustBeOwned(): Unit {
    let doc = XmlDocument()
    let r = doc.createElement("r")
    doc.appendChild(r)
    let alien = doc.createElement("alien") // 未挂接
    let target = doc.createElement("t")
    r.appendChild(target)
    // 以非本元素子节点作为 reference 时抛错
    let newChild = doc.createElement("n")
    var threw = false
    try {
        r.insertChildBefore(alien, newChild)
    } catch (_: XmlException) { threw = true }
    @Expect(threw, true)
}

@Test
func testRemoveChildReturnsFalseForNonChild(): Unit {
    let doc = XmlDocument()
    let r = doc.createElement("r")
    doc.appendChild(r)
    let alien = doc.createElement("alien")
    @Expect(r.removeChild(alien), false)
}

@Test
func testSelfInsertionRejected(): Unit {
    let doc = XmlDocument()
    let r = doc.createElement("r")
    doc.appendChild(r)
    var threw = false
    try {
        r.appendChild(r)
    } catch (_: XmlException) { threw = true }
    @Expect(threw, true)
}

@Test
func testInsertingDocumentAsChildRejected(): Unit {
    let doc = XmlDocument()
    let r = doc.createElement("r")
    doc.appendChild(r)
    var threw = false
    try {
        r.appendChild(doc)
    } catch (_: XmlException) { threw = true }
    @Expect(threw, true)
}

@Test
func testCrossDocumentAppendAtDocumentLevelRejected(): Unit {
    let d1 = XmlDocument()
    let d2 = XmlDocument()
    // d2 的元素被尝试塞进 d1 的顶层
    let alien = d2.createElement("a")
    var threw = false
    try {
        d1.appendChild(alien)
    } catch (_: XmlException) { threw = true }
    @Expect(threw, true)
}

@Test
func testDocumentFirstLastChildAndRemove(): Unit {
    let doc = XmlDocument()
    @Expect(doc.firstChild.isNone(), true)
    @Expect(doc.lastChild.isNone(), true)

    let decl = doc.createDeclaration()
    let root = doc.createElement("r")
    doc.appendChild(decl)
    doc.appendChild(root)
    match (doc.firstChild) {
        case Some(n) => @Assert(refEq(n, decl))
        case None => @Fail("firstChild missing")
    }
    match (doc.lastChild) {
        case Some(n) => @Assert(refEq(n, root))
        case None => @Fail("lastChild missing")
    }
    // removeChild on detached node → false
    let loose = doc.createComment("loose")
    @Expect(doc.removeChild(loose), false)
    // removeChild on actual child → true + removeSelf of the root delegates here
    @Expect(root.removeSelf(), true)
    @Expect(doc.rootElement.isNone(), true)
    // Second removal is a no-op
    @Expect(doc.removeChild(root), false)
}

@Test
func testDocumentRemoveChildRejectsCrossDocumentNode(): Unit {
    // inDocFlag=true only after owning insert; we simulate by linking in d1 then asking d2.
    let d1 = XmlDocument()
    let d2 = XmlDocument()
    let c = d1.createComment("x")
    d1.appendChild(c)
    @Expect(d2.removeChild(c), false)
}

@Test
func testTextContentSkipsCommentAndDeclaration(): Unit {
    // 覆盖 collectTextContent 的 `case _ => ()` 分支：非 Text / 非 Element
    // 子节点（comment / declaration / unknown）不应计入 textContent。
    let doc = XmlDocument()
    let r = doc.createElement("r")
    doc.appendChild(r)
    r.appendChild(doc.createText("a"))
    r.appendChild(doc.createComment("hide"))
    r.appendChild(doc.createUnknown("also-hide"))
    r.appendChild(doc.createText("b"))
    @Expect(r.textContent(), "ab")
}
