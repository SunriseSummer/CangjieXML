/*
 * writer — ElementStack：XmlWriter 元素栈（轻量）
 *
 * 把栈操作抽出一个小类，便于测试且保持主类专注状态机。
 */
package cangjie_xml.writer

import std.collection.*

class ElementStack {
    private let frames: ArrayList<ElementFrame>

    public init() {
        this.frames = ArrayList<ElementFrame>()
    }

    public func push(frame: ElementFrame): Unit {
        frames.add(frame)
    }

    public func pop(): ElementFrame {
        let last = frames.size - 1
        let f = frames[last]
        frames.remove(at: last)
        return f
    }

    public func top(): ElementFrame {
        return frames[frames.size - 1]
    }

    public func isEmpty(): Bool {
        return frames.size == 0
    }

    public func size(): Int64 {
        return frames.size
    }

    /** 将栈顶帧 `leafTextOnly` 置 `false`，`hasAnyChild` 置 `true`，表示写入了非文本子节点。 */
    public func markNonLeafChild(): Unit {
        if (frames.size == 0) {
            return
        }
        let idx = frames.size - 1
        var f = frames[idx]
        f.leafTextOnly = false
        f.hasAnyChild = true
        frames[idx] = f
    }

    /** 将栈顶帧标记"已写入至少一个子节点"（用于 Text / CDATA 之后仍可能自闭合的判断）。 */
    public func markAnyChild(): Unit {
        if (frames.size == 0) {
            return
        }
        let idx = frames.size - 1
        var f = frames[idx]
        f.hasAnyChild = true
        frames[idx] = f
    }
}
