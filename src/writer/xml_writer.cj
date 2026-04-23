package cangjie_xml.writer

import cangjie_xml.dom.*
import cangjie_xml.internal.*

/**
 * XML 写出器：把 DOM 子树序列化为 XML 文本并写入指定 `XmlSink`。
 *
 * ## 设计要点
 *
 * 1. **配置显式化**：所有行为由 `XmlWriteOptions` 控制，不存在全局静态开关——
 *    相同 DOM + 相同 options 必然产生相同输出（确定性契约，见 DESIGN §13.2）。
 * 2. **不借助 Visit 机制**：M2 阶段直接递归下降即可；M5 引入 `XmlVisitor` 后，
 *    `XmlWriter` 可以改写为 "`accept(writer)` 驱动输出" 而不变更对外签名。
 * 3. **低侵入**：Writer 不读也不写 DOM 内部字段，仅通过 `XmlNode` 的公共导航
 *    API 遍历——这意味着 Writer 完全可以跑在"别的 DOM 实现"上（未来 RFC-A
 *    流式事件输出的一致性基础）。
 *
 * ## 美化与紧凑
 *
 * - `options.compact = true`：节点之间不添加空白、换行；元素与其文本 / 子元素
 *   紧凑相邻。
 * - `options.compact = false`：每个"块级"节点独占一行，嵌套使用 `options.indent`
 *   缩进。**特殊约定**：若元素仅有一个 `XmlText` 子节点，则采用 tinyxml2 风格
 *   的内联形式 `<tag>text</tag>`，避免对短文本值产生冗余换行。
 *
 * ## 自闭合
 *
 * 没有子节点的元素统一输出为 `<name/>`。
 */
public class XmlWriter {
    private let _sink: XmlSink
    private let _opts: XmlWriteOptions
    private var _depth: Int64 = 0
    private var _atLineStart: Bool = true

    public init(sink: XmlSink, options!: XmlWriteOptions = XmlWriteOptions.default_()) {
        this._sink = sink
        this._opts = options
    }

    // ==================================================================
    // 入口 API
    // ==================================================================

    /**
     * 写出整个文档。
     *
     * 顺序与 DOM 顶层顺序一致。根据 `options.writeBom` / `options.writeDeclaration`
     * 决定是否输出 BOM 与 XML 声明。
     */
    public func writeDocument(doc: XmlDocument): Unit {
        if (_opts.writeBom || doc.writeBom) {
            _sink.write(UTF8_BOM_STRING)
        }

        // 处理声明
        if (_opts.writeDeclaration) {
            match (doc.declaration) {
                case Some(d) => _writeDeclaration(d)
                case None => _writeDefaultDeclaration()
            }
        }

        // 写其他顶层节点（跳过声明——已单独处理）
        for (n in doc.childNodes()) {
            match (n.kind()) {
                case Declaration(_) => ()
                case _ => _writeNode(n)
            }
        }
        _sink.flush()
    }

    /**
     * 写出单个元素子树（不输出文档声明 / BOM）。
     *
     * 适合把"片段"写成字符串的场景，例如把某个 `<chapter>` 元素独立序列化。
     */
    public func writeElement(el: XmlElement): Unit {
        _writeNode(el)
        _sink.flush()
    }

    /**
     * 按节点类型分派写出单个节点（不写声明 / BOM）。
     *
     * 文档类型会被展开为其顶层节点序列。
     */
    public func writeNode(node: XmlNode): Unit {
        match (node.kind()) {
            case Document(d) => writeDocument(d)
            case _ => _writeNode(node)
        }
    }

    // ==================================================================
    // 分派
    // ==================================================================

    private func _writeNode(node: XmlNode): Unit {
        match (node.kind()) {
            case Document(_)    => () // document 在 writeDocument 中处理
            case Element(e)     => _writeElement(e)
            case Text(t)        => _writeText(t)
            case Comment(c)     => _writeComment(c)
            case Declaration(d) => _writeDeclaration(d)
            case Unknown(u)     => _writeUnknown(u)
        }
    }

    // ==================================================================
    // 各节点写出
    // ==================================================================

    private func _writeDeclaration(d: XmlDeclaration): Unit {
        _indentIfNeeded()
        _sink.write("<?")
        _sink.write(d.value)
        _sink.write("?>")
        _maybeNewline()
    }

    private func _writeComment(c: XmlComment): Unit {
        _indentIfNeeded()
        _sink.write("<!--")
        _sink.write(c.value)
        _sink.write("-->")
        _maybeNewline()
    }

    private func _writeUnknown(u: XmlUnknown): Unit {
        _indentIfNeeded()
        _sink.write("<!")
        _sink.write(u.value)
        _sink.write(">")
        _maybeNewline()
    }

    private func _writeText(t: XmlText): Unit {
        // 文本节点的缩进策略由上层元素决定；这里只负责内容本身。
        if (t.isCdata) {
            _sink.write(escapeCdata(t.value))
        } else {
            _sink.write(escapeText(t.value))
        }
    }

    private func _writeElement(el: XmlElement): Unit {
        _indentIfNeeded()

        _sink.write("<")
        _sink.write(el.name)
        // 属性：按插入顺序输出
        for (a in el.attributes()) {
            _sink.write(" ")
            _sink.write(a.name)
            _sink.write("=\"")
            _sink.write(escapeAttribute(a.value))
            _sink.write("\"")
        }

        // 空元素：自闭合
        match (el.firstChild) {
            case None =>
                _sink.write("/>")
                _maybeNewline()
                return
            case Some(_) => ()
        }

        _sink.write(">")

        // 选择排版模式：
        // - 若任一子节点是 Text/CDATA，采用**内联模式**（不在子节点之间插入空白），
        //   以免破坏 XML 中"文本空白具有语义"的约定；
        // - 否则采用**块级模式**：每个子节点独占一行，并递增缩进。
        if (_hasTextChild(el)) {
            for (child in el.childNodes()) {
                _writeNodeInline(child)
            }
            _sink.write("</")
            _sink.write(el.name)
            _sink.write(">")
            _maybeNewline()
            return
        }

        // 块级模式：换行，缩进内部，结束标签回到当前层
        _maybeNewline()
        _depth++
        for (child in el.childNodes()) {
            _writeNode(child)
        }
        _depth--
        _indentIfNeeded()
        _sink.write("</")
        _sink.write(el.name)
        _sink.write(">")
        _maybeNewline()
    }

    /**
     * 内联模式写出一个子节点：不改变 `_atLineStart`，不插入换行 / 缩进。
     * 调用方（父元素）已在行内。
     */
    private func _writeNodeInline(node: XmlNode): Unit {
        match (node.kind()) {
            case Document(_) => ()
            case Element(e) => _writeElementInline(e)
            case Text(t) => _writeText(t)
            case Comment(c) =>
                _sink.write("<!--")
                _sink.write(c.value)
                _sink.write("-->")
            case Declaration(d) =>
                _sink.write("<?")
                _sink.write(d.value)
                _sink.write("?>")
            case Unknown(u) =>
                _sink.write("<!")
                _sink.write(u.value)
                _sink.write(">")
        }
    }

    /** 内联上下文中的元素输出：全程单行，无换行缩进。 */
    private func _writeElementInline(el: XmlElement): Unit {
        _sink.write("<")
        _sink.write(el.name)
        for (a in el.attributes()) {
            _sink.write(" ")
            _sink.write(a.name)
            _sink.write("=\"")
            _sink.write(escapeAttribute(a.value))
            _sink.write("\"")
        }
        match (el.firstChild) {
            case None =>
                _sink.write("/>")
                return
            case Some(_) => ()
        }
        _sink.write(">")
        for (child in el.childNodes()) {
            _writeNodeInline(child)
        }
        _sink.write("</")
        _sink.write(el.name)
        _sink.write(">")
    }

    // ==================================================================
    // 排版辅助
    // ==================================================================

    /** 若当前处于新行起点且是美化模式，则写出当前深度对应的缩进。 */
    private func _indentIfNeeded(): Unit {
        if (_opts.compact) {
            return
        }
        if (_atLineStart) {
            var i = 0
            while (i < _depth) {
                _sink.write(_opts.indent)
                i++
            }
            _atLineStart = false
        }
    }

    /** 美化模式下写入行尾；紧凑模式下 no-op。 */
    private func _maybeNewline(): Unit {
        if (_opts.compact) {
            return
        }
        _sink.write(_opts.lineEnd)
        _atLineStart = true
    }

    private static func _hasTextChild(el: XmlElement): Bool {
        var cur = el.firstChild
        while (let Some(n) <- cur) {
            match (n.kind()) {
                case Text(_) => return true
                case _ => ()
            }
            cur = n.nextSibling
        }
        false
    }

    private func _writeDefaultDeclaration(): Unit {
        _indentIfNeeded()
        _sink.write("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
        _maybeNewline()
    }
}
