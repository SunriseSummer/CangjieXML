/*
 * tree — Node：DOM 节点的 sealed 根接口
 *
 * 对应 libxml2: `tree.c` 中 `xmlNode` 及其子类型；libxml2 用 C struct + 大量
 * `xmlNodeType` 枚举做变体，用户侧只能靠 `if node->type == XML_...` 判别。
 * CangjieXML 把它建模为 `sealed interface Node`，由同包内若干 `class`/`struct`
 * 分支实现。下游走 `match` 时编译器能做**穷举性**检查，比裸指针 + 类型码安全
 * 得多。
 *
 * 本阶段（Phase 4a MVP）只实现只读 DOM —— 节点由 `DocumentBuilder` 从
 * `Iterator<SaxEvent>` 构造完成后即视为**结构稳定**。不提供 append / remove /
 * replace 等变更 API；这些会在 Phase 4b 补齐（届时需要同时维护父/子/兄弟链
 * 的一致性不变量）。
 *
 * 与 libxml2 的关键差异：
 *   - `Attr` **不是** `Node` —— 对齐 W3C DOM Level 2 以后的约定（libxml2 继续把
 *     属性塞进 `xmlAttr`，同样非 `xmlNode.children` 成员，但共享 `xmlGenericAttr`
 *     基础布局）；CangjieXML 直接让属性成为 `Element.attributes` 的独立值类
 *     型，避免混淆。
 *   - `parent` 字段类型为 `?Element` 而非 `?Node` —— 在良构 XML 中任何非根节点
 *     的父必然是元素，类型系统直接表达这一不变式，排除运行时误判。
 */
package cangjie_xml.tree

import cangjie_xml.core.*

/* ---------- Node sealed 根接口 ---------- */

/**
 * DOM 所有节点类型的公共接口。用 `sealed` 限制实现范围在本包内：
 * 下游只能通过 `match (node) { case d: Document => ... }` 走穷举分派。
 *
 * 包内实现列表（与 `NodeKind` 一一对应）：
 *   - `Document`（根容器；唯一无 `parent` 的 Node）
 *   - `Element`（具名元素，持有子节点与属性）
 *   - `TextNode`（普通字符数据）
 *   - `CdataSection`（CDATA 段，语义等同 Text 但序列化时需保留包装）
 *   - `CommentNode`（注释）
 *   - `PiNode`（处理指令）
 *   - `DoctypeNode`（DOCTYPE 头，仅保留名字 —— 本阶段不解析内部子集）
 */
sealed interface Node <: ToString {
    /** 词法起点在源文档中的位置。构建自合成节点时为 `Position.unknown()`。 */
    func position(): Position

    /** 节点类型标签。用于跨语言 / 跨 API 的快速判别；`match` 仍应优先用类型模式。 */
    func nodeKind(): NodeKind
}

/* ---------- NodeKind 枚举 ---------- */

/**
 * 节点类型标签。对应 W3C DOM Level 2 `Node.nodeType` 但仅保留本 MVP 覆盖的七种；
 * 额外的 `EntityReference` / `DocumentFragment` / `Notation` 等留待后续阶段。
 */
public enum NodeKind <: Equatable<NodeKind> & ToString {
    | DocumentNode
    | ElementNode
    | TextNodeKind
    | CdataSectionNode
    | CommentNodeKind
    | ProcessingInstructionNode
    | DoctypeNodeKind

    public operator func ==(that: NodeKind): Bool {
        return this.ordinal() == that.ordinal()
    }

    public operator func !=(that: NodeKind): Bool {
        return !(this == that)
    }

    /** 稳定的整数序号，便于放进 `HashMap<Int64, _>` 或跨 FFI 传递。 */
    public func ordinal(): Int64 {
        match (this) {
            case DocumentNode => return 0
            case ElementNode => return 1
            case TextNodeKind => return 2
            case CdataSectionNode => return 3
            case CommentNodeKind => return 4
            case ProcessingInstructionNode => return 5
            case DoctypeNodeKind => return 6
        }
    }

    public func toString(): String {
        match (this) {
            case DocumentNode => return "Document"
            case ElementNode => return "Element"
            case TextNodeKind => return "Text"
            case CdataSectionNode => return "CdataSection"
            case CommentNodeKind => return "Comment"
            case ProcessingInstructionNode => return "ProcessingInstruction"
            case DoctypeNodeKind => return "Doctype"
        }
    }
}
