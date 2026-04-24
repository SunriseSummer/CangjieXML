package cangjie_xml.visit

import cangjie_xml.dom.*

/**
 * 经典 OO 访问者接口。
 *
 * ## 与 tinyxml2 `XMLVisitor` 的对齐
 *
 * tinyxml2 定义：
 *
 * ```cpp
 * virtual bool VisitEnter(const XMLDocument&) { return true; }
 * virtual bool VisitExit(const XMLDocument&)  { return true; }
 * virtual bool VisitEnter(const XMLElement&, const XMLAttribute*) { return true; }
 * virtual bool VisitExit(const XMLElement&)   { return true; }
 * virtual bool Visit(const XMLDeclaration&)   { return true; }
 * virtual bool Visit(const XMLText&)          { return true; }
 * virtual bool Visit(const XMLComment&)       { return true; }
 * virtual bool Visit(const XMLUnknown&)       { return true; }
 * ```
 *
 * CangjieXML 的差异：
 *
 * 1. **`visitEnter(XmlElement)` 不额外传属性链表**。tinyxml2 的 `XMLAttribute*`
 *    是其内部链表头指针，仓颉侧直接在访问者里 `element.attributes()` 即可，
 *    签名更干净。
 * 2. **返回语义保持对齐**：`visitEnter` 返回 `false` 跳过子节点；`visit(...)`
 *    返回 `false` 在当前 dispatch 点中止整棵遍历。
 * 3. 使用仓颉的 interface 默认实现，使子类只实现关心的几个方法即可。
 *
 * ## 返回值约定
 *
 * - `visitEnter(...)` 返回 `false`：**不进入当前节点的子树**，但继续处理兄弟节点；
 *   对应的 `visitExit(...)` **不会被调用**——与 tinyxml2 行为一致。
 * - `visit(...)`（叶子节点）返回 `false`：立即终止整次 `accept`，
 *   `accept` 本身会返回 `false` 向上传播。
 * - `visitExit(...)` 的返回值仅在"决定是否继续处理后续兄弟节点"层面生效，
 *   也就是说：`false` 表示"我看完这棵子树就够了，外层别继续走了"。
 */
public interface XmlVisitor {

    func visitEnter(document: XmlDocument): Bool {
        true
    }

    func visitExit(document: XmlDocument): Bool {
        true
    }

    func visitEnter(element: XmlElement): Bool {
        true
    }

    func visitExit(element: XmlElement): Bool {
        true
    }

    func visit(text: XmlText): Bool {
        true
    }

    func visit(comment: XmlComment): Bool {
        true
    }

    func visit(declaration: XmlDeclaration): Bool {
        true
    }

    func visit(unknown: XmlUnknown): Bool {
        true
    }
}
