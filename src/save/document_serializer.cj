/*
 * save — DocumentSerializer：DOM → XML 文本
 *
 * 对应 libxml2: `xmlsave.c` 的 `xmlSaveDoc` / `xmlNodeDumpOutputInternal`。
 *
 * 设计要点：
 *   - 基础形态：`DocumentSerializer.toString(doc)` 返回 UTF-8 `String`。不做编码
 *     转换；Phase 5b 引入 `IoSink` 后再接 `EncodingSink`。
 *   - 遍历策略：显式"前序"深度遍历（迭代展开 — 避免极深嵌套 XML 触发栈溢出；
 *     libxml2 同样用循环 + 队列）。
 *   - 缩进规则（`indent = true`）：
 *       * Element 开始标签前插入换行 + 缩进；
 *       * 只含叶子文本的 Element 保持同行（避免给文本注入空白改变语义）；
 *       * Comment / PI 同 Element 规则处理。
 *     与 libxml2 `xmlSaveFormatFile` 默认行为对齐。
 *   - 命名空间：`Attr.isNamespaceDeclaration = true` 的属性原样写出（`xmlns` /
 *     `xmlns:p`）。Phase 5a 不做最小化 / 去重。
 *
 * 实现被按关注点拆到同包 extend 文件（与 `XmlParser` 同样的拆分手法，主类
 * 只能访问自己的成员；extend 之间调用自由）：
 *   - `document_serializer_nodes.cj` — 元素 / 属性 / 子树 / 缩进 / Comment / PI / CDATA
 *
 * 主类体（本文件）仅保留公开入口与字段。
 */
package cangjie_xml.save

import cangjie_xml.tree.*

public class DocumentSerializer {
    let opts: SerializeOptions
    let sb: StringBuilder

    public init(opts!: SerializeOptions = SerializeOptions()) {
        this.opts = opts
        this.sb = StringBuilder()
    }

    /* ---------- 便利入口 ---------- */

    /** 一次性：把 Document 序列化为 String。 */
    public static func toString(doc: Document, opts!: SerializeOptions = SerializeOptions()): String {
        return DocumentSerializer(opts: opts).write(doc)
    }

    /** 仅序列化单个元素子树，不含 XML 声明 / prolog / epilog。 */
    public static func elementToString(el: Element, opts!: SerializeOptions = SerializeOptions()): String {
        return DocumentSerializer(opts: opts).writeElementOnly(el)
    }

    /**
     * 仅序列化单个节点。对应 .NET `XmlReader.ReadInnerXml` 下游常用的"把任意
     * Node 还原成 XML 文本"需求。
     *
     * - `Element`：等价 `elementToString`；
     * - `TextNode`：返回 XML 转义后的字符数据；
     * - `CdataSection`：原样包裹为 `<![CDATA[...]]>`（除非 `cdataAsText = true`）；
     * - `CommentNode` / `PiNode`：输出 `<!--...-->` / `<?target data?>`；
     * - `Document` / `DoctypeNode`：抛 `IllegalArgumentException`（这两种不是
     *   "内联节点"，应走 `toString(doc)`）。
     */
    public static func nodeToString(n: Node, opts!: SerializeOptions = SerializeOptions()): String {
        return DocumentSerializer(opts: opts).writeNodeOnly(n)
    }

    /* ---------- 主入口（委派到 extend 实现） ---------- */

    public func write(doc: Document): String {
        return serializeDocument(this, doc)
    }

    /** 内部入口：仅序列化元素子树。extend 负责实现。 */
    public func writeElementOnly(el: Element): String {
        return serializeElementOnly(this, el)
    }

    /** 内部入口：仅序列化单个节点。extend 负责实现。 */
    public func writeNodeOnly(n: Node): String {
        return serializeNodeOnly(this, n)
    }
}

/* 包级转发函数：主类体内不能直接调用 extend 的成员；我们用
   `serializeDocument` / `serializeElementOnly` / `serializeNodeOnly` 作为桥接。 */
func serializeDocument(s: DocumentSerializer, doc: Document): String {
    return s.runSerializeDocument(doc)
}

func serializeElementOnly(s: DocumentSerializer, el: Element): String {
    return s.runSerializeElementOnly(el)
}

func serializeNodeOnly(s: DocumentSerializer, n: Node): String {
    return s.runSerializeNodeOnly(n)
}
