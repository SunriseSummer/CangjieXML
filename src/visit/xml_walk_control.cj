package cangjie_xml.visit

/**
 * 函数式遍历的控制信号。
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
