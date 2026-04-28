package fastxml.error

/**
 * 表示源文本中的一个位置坐标
 *
 * - `offset`：从文档起始（忽略 BOM 之后）算起的 **字节偏移**
 *   纯 ASCII 输入下与"码点偏移"完全一致；含多字节 UTF-8 时按字节计
 *   定位用 `line` / `column` 更直观；`offset` 主要用于错误信息呈现
 * - `line`：行号，1 起
 * - `column`：列号（以 UTF-8 码点计），1 起
 */
public struct SourcePos <: ToString {
    public let offset: Int64
    public let line: Int64
    public let column: Int64

    public init(offset: Int64, line: Int64, column: Int64) {
        this.offset = offset
        this.line = line
        this.column = column
    }

    /**
     * 返回一个表示"零位置"的哨兵值（offset=0, line=1, column=1）
     *
     * 适合用于 DOM 手工构造、测试或尚未记录位置信息的场景
     */
    public static func zero(): SourcePos {
        SourcePos(0, 1, 1)
    }

    public func toString(): String {
        "line ${line}, column ${column} (offset ${offset})"
    }
}
