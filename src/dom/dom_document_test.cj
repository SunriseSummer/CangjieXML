package fastxml.dom

import std.unittest.*
import std.unittest.testmacro.*
import fastxml.error.*

// ====================================================================
// XmlDocument 行为测试：顶层节点约束、工厂、clear。
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
func testVersionConstant(): Unit {
    // 验证 DOM 模块自身的基本稳定性（版本常量测试放在根包自身的测试文件里）。
    let doc = XmlDocument()
    @Assert(refEq(doc.document, doc))
}
