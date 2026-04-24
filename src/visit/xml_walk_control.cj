package cangjie_xml.visit

/**
 * 函数式遍历的控制信号。
 *
 * 与 `XmlVisitor` 的 `Bool` 返回相比，`XmlWalkControl` 把"跳过子树"与
 * "中止全部"两种意图显式区分开：在 tinyxml2 的原始访问者中这两者都用
 * `false` 表示，调用方只能依靠文档约定去推测语义。`walk` 面向的是更现代、
 * 更轻量的函数式风格，所以选择显式枚举。
 *
 * - `Continue`：正常继续，进入子节点、处理下一个兄弟。
 * - `SkipChildren`：当前节点不再下钻，但继续处理其兄弟节点。
 * - `Stop`：立即终止整次 `walk`，不再访问任何节点。
 */
public enum XmlWalkControl {
    | Continue
    | SkipChildren
    | Stop
}
