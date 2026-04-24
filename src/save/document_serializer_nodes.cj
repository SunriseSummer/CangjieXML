/*
 * save — DocumentSerializer：元素子树 + prolog / epilog / 声明序列化
 *
 * 拆自主文件，集中全部输出逻辑。每个函数圈复杂度 ≤ 6。
 * 主类体受 Cangjie 限制（不能调 extend 成员）只保留字段 + 公开入口；
 * 这里通过包级 `serializeDocument` / `serializeElementOnly` 桥接。
 */
package cangjie_xml.save

import cangjie_xml.core.*
import cangjie_xml.parser.*
import cangjie_xml.tree.*

extend DocumentSerializer {
    /* ---------- 顶层：Document / Element-only ---------- */

    func runSerializeDocument(doc: Document): String {
        writeXmlDeclarationIfAny(doc.xmlDecl)
        writeDoctypeIfAny(doc.doctype)
        for (n in doc.prolog()) {
            writeProlog(n)
        }
        writeElementTree(doc.root, 0)
        for (n in doc.epilog()) {
            writeEpilog(n)
        }
        return sb.toString()
    }

    func runSerializeElementOnly(el: Element): String {
        writeElementTree(el, 0)
        return sb.toString()
    }

    /* ---------- Prolog / Epilog / XML 声明 / DOCTYPE ---------- */

    func writeXmlDeclarationIfAny(decl: XmlDecl): Unit {
        if (opts.omitXmlDeclaration) {
            return
        }
        if (opts.omitSyntheticXmlDeclaration && decl.isSynthetic) {
            return
        }
        sb.append("<?xml version=\"")
        sb.append(decl.version)
        sb.append(r'"')
        match (decl.encoding) {
            case Some(e) =>
                sb.append(" encoding=\"")
                sb.append(e)
                sb.append(r'"')
            case None => ()
        }
        match (decl.standalone) {
            case Yes => sb.append(" standalone=\"yes\"")
            case No => sb.append(" standalone=\"no\"")
            case Unspecified => ()
        }
        sb.append("?>")
        if (opts.indent) {
            sb.append(opts.lineSeparator)
        }
    }

    func writeDoctypeIfAny(doctype: ?DoctypeNode): Unit {
        match (doctype) {
            case Some(d) =>
                sb.append("<!DOCTYPE ")
                sb.append(d.name)
                sb.append(r'>')
                if (opts.indent) {
                    sb.append(opts.lineSeparator)
                }
            case None => ()
        }
    }

    func writeProlog(n: Node): Unit {
        writeStandaloneNode(n)
        if (opts.indent) {
            sb.append(opts.lineSeparator)
        }
    }

    func writeEpilog(n: Node): Unit {
        if (opts.indent) {
            sb.append(opts.lineSeparator)
        }
        writeStandaloneNode(n)
    }

    func writeStandaloneNode(n: Node): Unit {
        match (n) {
            case c: CommentNode => writeComment(c)
            case p: PiNode => writePi(p)
            case _ => () // prolog/epilog 里只应出现 Comment/Pi
        }
    }

    /* ---------- 元素 + 子树 ---------- */

    func writeElementTree(el: Element, depth: Int64): Unit {
        if (isLeafTextElement(el)) {
            writeLeafTextElement(el, depth)
            return
        }
        writeElementWithChildren(el, depth)
    }

    /**
     * 只含直接 Text / CDATA 子节点（不含子元素、Comment、PI）的元素按"同行"
     * 写出，避免缩进插入空白改变字符数据语义。
     * 空元素也走这条路径，被 `writeStartTag(selfClosing=true)` 自闭合为 `<a/>`。
     */
    func isLeafTextElement(el: Element): Bool {
        if (el.childCount() == 0) {
            return true
        }
        for (c in el.children()) {
            match (c) {
                case _: TextNode => ()
                case _: CdataSection => ()
                case _ => return false
            }
        }
        return true
    }

    func writeLeafTextElement(el: Element, depth: Int64): Unit {
        writeIndent(depth)
        if (el.childCount() == 0) {
            writeStartTag(el, selfClosing: true)
            return
        }
        writeStartTag(el, selfClosing: false)
        for (c in el.children()) {
            match (c) {
                case t: TextNode => sb.append(escapeXml(t.data))
                case c2: CdataSection => writeCdata(c2)
                case _ => ()
            }
        }
        writeEndTag(el)
    }

    func writeElementWithChildren(el: Element, depth: Int64): Unit {
        writeIndent(depth)
        writeStartTag(el, selfClosing: false)
        for (c in el.children()) {
            writeChildNode(c, depth + 1)
        }
        writeIndent(depth)
        writeEndTag(el)
    }

    func writeChildNode(n: Node, depth: Int64): Unit {
        match (n) {
            case e: Element => writeElementTree(e, depth)
            case t: TextNode => sb.append(escapeXml(t.data))
            case c: CdataSection => writeCdataAtDepth(c, depth)
            case cm: CommentNode =>
                writeIndent(depth)
                writeComment(cm)
            case pi: PiNode =>
                writeIndent(depth)
                writePi(pi)
            case _ => ()
        }
    }

    /* ---------- 标签 ---------- */

    func writeStartTag(el: Element, selfClosing!: Bool): Unit {
        sb.append(r'<')
        sb.append(el.qname.lexical())
        for (a in el.attributes()) {
            sb.append(r' ')
            sb.append(a.qname.lexical())
            sb.append("=\"")
            sb.append(escapeXml(a.value, forAttribute: true))
            sb.append(r'"')
        }
        if (selfClosing) {
            sb.append("/>")
        } else {
            sb.append(r'>')
        }
    }

    func writeEndTag(el: Element): Unit {
        sb.append("</")
        sb.append(el.qname.lexical())
        sb.append(r'>')
    }

    /* ---------- 叶子：CDATA / Comment / PI ---------- */

    func writeCdata(c: CdataSection): Unit {
        if (opts.cdataAsText) {
            sb.append(escapeXml(c.data))
            return
        }
        sb.append("<![CDATA[")
        sb.append(c.data)
        sb.append("]]>")
    }

    func writeCdataAtDepth(c: CdataSection, depth: Int64): Unit {
        writeIndent(depth)
        writeCdata(c)
    }

    func writeComment(c: CommentNode): Unit {
        sb.append("<!--")
        sb.append(c.data)
        sb.append("-->")
    }

    func writePi(p: PiNode): Unit {
        sb.append("<?")
        sb.append(p.target)
        if (p.data.size > 0) {
            sb.append(r' ')
            sb.append(p.data)
        }
        sb.append("?>")
    }

    /* ---------- 缩进 ---------- */

    /**
     * 缩进规则：
     *   - `indent=false`：不插入任何空白；
     *   - `indent=true`：换行 + `depth` 份 `indentString`；
     *   - 顶层首行换行可能与声明后的换行重复，但 parser 会把它作为合法
     *     prolog 空白忽略，不影响语义。
     */
    func writeIndent(depth: Int64): Unit {
        if (!opts.indent) {
            return
        }
        sb.append(opts.lineSeparator)
        var i = 0
        while (i < depth) {
            sb.append(opts.indentString)
            i += 1
        }
    }
}
