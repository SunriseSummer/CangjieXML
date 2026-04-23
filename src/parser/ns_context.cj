/*
 * parser — 不可变命名空间上下文
 *
 * 对应 libxml2: `parser.c` / `SAX2.c` 中的 `xmlNs*` 链表（`ns->next` / `ns->prefix`
 * / `ns->href`），但设计上有本质差异：
 *
 *   - libxml2 使用 **全局指针链表 + 指针逸出** 的可变模型：随着解析器进入 / 离开
 *     元素，命名空间节点被 push / pop，`xmlNs*` 指针可能指向已被修改的父节点。
 *     这是若干历史 CVE 的根因（`xmlNsPtr.next` 在作用域错误时悬垂 / 混淆）。
 *
 *   - 本实现采用 **不可变持久化栈**：`push` 返回新实例，结构共享父引用。每个
 *     `StartElement` 事件携带自己的 `NsContext` 快照；事件消费方任意保存该快照
 *     都不会影响后续解析过程，也杜绝了作用域错配。
 *
 * 数据结构：单链表 + 栈顶计数；`resolve(prefix)` 自栈顶向根线性搜索。对于典型
 * XML 文档的命名空间深度（< 10）此实现的常数比 HashMap 更小；对深度极大的合成
 * 文档亦不会炸，最坏 O(depth)。
 */
package cangjie_xml.parser

import std.collection.*

/** `xml` 前缀绑定的固定 URI（W3C Namespaces §3）。 */
public const XML_NAMESPACE_URI: String = "http://www.w3.org/XML/1998/namespace"
/** `xmlns` 前缀绑定的固定 URI（W3C Namespaces §3）。用户不应绑定此 URI。 */
public const XMLNS_NAMESPACE_URI: String = "http://www.w3.org/2000/xmlns/"

public class NsContext {
    // 空前缀（默认命名空间）用 None 表示。`uri` None 表示"显式解绑"（
    // W3C Namespaces 1.1 允许 `xmlns:p=""` 解绑前缀；XML 1.0 下解析器会报错，
    // 这里数据结构仍支持，语义约束在 parser 层兜）。
    private let prefix: ?String
    private let uri: ?String
    private let parent: ?NsContext
    private let depth: Int64

    private init(prefix: ?String, uri: ?String, parent: ?NsContext, depth: Int64) {
        this.prefix = prefix
        this.uri = uri
        this.parent = parent
        this.depth = depth
    }

    /** 根上下文：仅预置 `xml` 前缀。 */
    public static func root(): NsContext {
        // 底层链：root (xml -> XML_NAMESPACE_URI)
        return NsContext(Some("xml"), Some(XML_NAMESPACE_URI), None, 1)
    }

    /**
     * 压入一条新绑定，返回新的上下文。
     * @param prefix `None` 表示 xmlns 默认绑定
     * @param uri `None` / 空串表示解绑
     */
    public func push(prefix: ?String, uri: ?String): NsContext {
        let u = match (uri) {
            case Some(s) where s.size == 0 => None<String>
            case other => other
        }
        return NsContext(prefix, u, Some(this), this.depth + 1)
    }

    /**
     * 解析前缀到 URI。
     * - `None` 前缀 → 当前默认命名空间
     * - `Some("xml")` → 固定返回 `XML_NAMESPACE_URI`（即使用户错绑也保留正确值）
     * - 其他前缀：沿链向根查找，未绑定返回 `None`
     */
    public func resolve(prefix: ?String): ?String {
        // xml 是硬绑定
        match (prefix) {
            case Some(p) where p == "xml" => return Some(XML_NAMESPACE_URI)
            case Some(p) where p == "xmlns" => return Some(XMLNS_NAMESPACE_URI)
            case _ => ()
        }
        var cur: ?NsContext = Some(this)
        while (true) {
            match (cur) {
                case None => return None
                case Some(c) =>
                    if (nsEquals(c.prefix, prefix)) {
                        return c.uri
                    }
                    cur = c.parent
            }
        }
        return None
    }

    /** 默认命名空间的 URI（`None` 表示无默认）。 */
    public func defaultNs(): ?String {
        return resolve(None<String>)
    }

    /** 当前"栈深"（调试用）。 */
    public prop size: Int64 {
        get() {
            return depth
        }
    }

    /**
     * 获取**当前作用域链**中所有生效绑定的快照。
     * 返回 `(prefix, uri)` 列表，前缀 `None` 表示默认命名空间。
     * 对于同一前缀只保留**最内层**绑定（向根方向扫描遇到第一次就收录，后续跳过）。
     */
    public func bindings(): Array<(?String, ?String)> {
        let seen = HashSet<String>()
        var sawDefault = false
        let acc = ArrayList<(?String, ?String)>()
        var cur: ?NsContext = Some(this)
        while (true) {
            match (cur) {
                case None => break
                case Some(c) =>
                    match (c.prefix) {
                        case None =>
                            if (!sawDefault) {
                                sawDefault = true
                                acc.add((None<String>, c.uri))
                            }
                        case Some(p) =>
                            if (!seen.contains(p)) {
                                seen.add(p)
                                acc.add((Some(p), c.uri))
                            }
                    }
                    cur = c.parent
            }
        }
        return acc.toArray()
    }

    private static func nsEquals(a: ?String, b: ?String): Bool {
        match ((a, b)) {
            case (None, None) => return true
            case (Some(x), Some(y)) => return x == y
            case _ => return false
        }
    }
}
