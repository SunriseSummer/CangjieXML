package cangjie_xml.dom

import std.unittest.*
import std.unittest.testmacro.*
import cangjie_xml.error.*

// ====================================================================
// M1 DOM 内核：行为测试
//
// 按 ROADMAP §3 的测试重点组织：
//   - 子节点与兄弟关系正确
//   - 文档与节点的关联正确
//   - 属性顺序与覆盖行为正确
//   - XmlNodeKind 模式匹配穷举性明确
// ====================================================================

@Test
func testCreateEmptyDocument(): Unit {
    let doc = XmlDocument()
    @Expect(doc.rootElement.isSome(), false)
    @Expect(doc.declaration.isSome(), false)
    @Expect(doc.hasBom, false)
    @Expect(doc.writeBom, false)
    // document 属性：自指
    @Assert(refEq(doc.document, doc))
}

@Test
func testFactoryAttachesDocument(): Unit {
    let doc = XmlDocument()
    let el = doc.createElement("root")
    let t = doc.createText("hello")
    let c = doc.createComment("c")
    let d = doc.createDeclaration()
    let u = doc.createUnknown("DOCTYPE html")

    @Assert(refEq(el.document, doc))
    @Assert(refEq(t.document, doc))
    @Assert(refEq(c.document, doc))
    @Assert(refEq(d.document, doc))
    @Assert(refEq(u.document, doc))
}

@Test
func testAppendRootElement(): Unit {
    let doc = XmlDocument()
    let root = doc.createElement("catalog")
    doc.appendChild(root)
    match (doc.rootElement) {
        case Some(r) => @Assert(refEq(r, root))
        case None => @Assert(false)
    }
    // 根元素的父节点为 None（它是文档直接子节点）
    match (root.parent) {
        case None => ()
        case Some(_) => @Assert(false)
    }
}

@Test
func testDuplicateRootElementRejected(): Unit {
    let doc = XmlDocument()
    doc.appendChild(doc.createElement("a"))
    var caught = false
    try {
        doc.appendChild(doc.createElement("b"))
    } catch (_: XmlException) {
        caught = true
    }
    @Expect(caught, true)
}

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

@Test
func testKindExhaustivePatternMatch(): Unit {
    let doc = XmlDocument()
    let el = doc.createElement("e")
    let t = doc.createText("t")
    let c = doc.createComment("c")
    let d = doc.createDeclaration()
    let u = doc.createUnknown("u")

    func label(n: XmlNode): String {
        match (n.kind()) {
            case Document(_)    => "doc"
            case Element(_)     => "el"
            case Text(_)        => "t"
            case Comment(_)     => "c"
            case Declaration(_) => "d"
            case Unknown(_)     => "u"
        }
    }

    @Expect(label(doc), "doc")
    @Expect(label(el), "el")
    @Expect(label(t), "t")
    @Expect(label(c), "c")
    @Expect(label(d), "d")
    @Expect(label(u), "u")
}

@Test
func testDeclarationPlacement(): Unit {
    let doc = XmlDocument()
    let decl = doc.createDeclaration()
    doc.appendChild(decl)
    var caught = false
    try {
        doc.appendChild(doc.createDeclaration()) // 只允许一条
    } catch (_: XmlException) {
        caught = true
    }
    @Expect(caught, true)
    // Declaration 不能塞进 Element
    let root = doc.createElement("r")
    doc.appendChild(root)
    var caught2 = false
    try {
        root.appendChild(doc.createDeclaration())
    } catch (_: XmlException) {
        caught2 = true
    }
    @Expect(caught2, true)
}

@Test
func testTextForbiddenAtDocumentTopLevel(): Unit {
    let doc = XmlDocument()
    var caught = false
    try {
        doc.appendChild(doc.createText("bare"))
    } catch (_: XmlException) {
        caught = true
    }
    @Expect(caught, true)
}

@Test
func testDocumentClear(): Unit {
    let doc = XmlDocument()
    doc.appendChild(doc.createDeclaration())
    let root = doc.createElement("r")
    doc.appendChild(root)
    root.appendChild(doc.createElement("a"))
    doc.clear()
    @Expect(doc.rootElement.isSome(), false)
    @Expect(doc.declaration.isSome(), false)
    // root 现在是游离节点，但 document 仍指向该文档
    match (root.parent) {
        case None => ()
        case Some(_) => @Assert(false)
    }
    @Assert(refEq(root.document, doc))
    // 还能重新挂回去
    doc.appendChild(root)
    match (doc.rootElement) {
        case Some(r) => @Assert(refEq(r, root))
        case None => @Assert(false)
    }
}

@Test
func testVersionConstant(): Unit {
    // 验证 DOM 模块自身的基本稳定性（版本常量测试放在根包自身的测试文件里）。
    let doc = XmlDocument()
    @Assert(refEq(doc.document, doc))
}
