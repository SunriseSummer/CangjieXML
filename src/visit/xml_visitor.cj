package fastxml.visit

import fastxml.dom.*

/**
 * 经典 OO 访问者接口。
 *
 * 子类实现关心的几个方法即可，未实现的方法返回 `true` 走默认路径（依赖仓颉
 * interface 的默认实现）。
 *
 * ## 返回值约定
 *
 * - `visitEnter(...)` 返回 `false`：**不进入当前节点的子树**，但继续处理兄弟节点；
 *   对应的 `visitExit(...)` **不会被调用**——与 tinyxml2 行为一致。
 * - `visit(...)`（叶子节点）返回 `false`：立即终止整次 `accept`，
 *   `accept` 本身会返回 `false` 向上传播。
 * - `visitExit(...)` 的返回值仅在"决定是否继续处理后续兄弟节点"层面生效，
 *   `false` 表示"我看完这棵子树就够了，外层别继续走了"。
 *
 * ## 与 tinyxml2 `XMLVisitor` 的差异
 *
 * `visitEnter(XmlElement)` 不额外传属性链表——访问者内部直接调用
 * `element.attributes()` 即可。
 */
public interface XmlVisitor {

    func visitEnter(_: XmlDocument): Bool {
        true
    }

    func visitExit(_: XmlDocument): Bool {
        true
    }

    func visitEnter(_: XmlElement): Bool {
        true
    }

    func visitExit(_: XmlElement): Bool {
        true
    }

    func visit(_: XmlText): Bool {
        true
    }

    func visit(_: XmlComment): Bool {
        true
    }

    func visit(_: XmlDeclaration): Bool {
        true
    }

    func visit(_: XmlUnknown): Bool {
        true
    }
}
