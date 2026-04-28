package xlsx_to_csv

/**
 * A1 风格单元格引用解析工具
 *
 * xlsx 单元格的 `r` 属性形如 `"A1"` / `"BC27"`——前缀是列字母（A=1, Z=26,
 * AA=27…），后缀是 1 起的行号。列号在 OOXML 规范里上限 16384（XFD），本模块
 * 不额外限定上限，交由上层消费者决定是否截断
 *
 * 所有函数对非法输入返回 `None`——**不抛**异常，让调用者自行决定忽略还是
 * 汇报位置
 */

/**
 * 解析 A1 引用，返回 `(column, row)`，两者均为 **1 起**
 *
 * 非法输入返回 `None`。"合法"的定义：
 *
 * - 以若干 ASCII 字母（A–Z / a–z 都接受）开头；
 * - 紧跟若干 ASCII 数字；
 * - 字母段 / 数字段都至少有一个字符；
 * - 整串无多余字符
 *
 * 允许小写字母纯粹是容错——OOXML 规范里固定大写，但个别导出工具会写成
 * 小写。无需为此炸毁整个转换流程
 */
public func parseCellRef(r: String): ?(Int64, Int64) {
    let bytes = r.toArray()
    let n = bytes.size
    if (n == 0) { return None }

    // 字母段
    var i = 0
    var col: Int64 = 0
    while (i < n) {
        let b = bytes[i]
        let letter = letterValue(b)
        match (letter) {
            case None => break
            case Some(v) =>
                col = col * 26 + v
                i++
        }
    }
    if (i == 0 || i == n) {
        // 无字母段，或全是字母没有行号
        return None
    }

    // 数字段
    var row: Int64 = 0
    let digitStart = i
    while (i < n) {
        let b = bytes[i]
        if (b < b'0' || b > b'9') {
            return None                    // 数字段后还有多余字符
        }
        row = row * 10 + Int64(b - b'0')
        i++
    }
    if (i == digitStart || row == 0) {
        return None
    }
    Some((col, row))
}

/**
 * 把列字母解析成 1 起的列号；非字母返回 `None`
 *
 * 抽出独立函数，既让 `parseCellRef` 的主循环更紧凑，也方便未来如果要单独
 * 处理 `colSpans="1:13"` 这样的列范围字符串
 */
func letterValue(b: Byte): ?Int64 {
    if (b >= b'A' && b <= b'Z') {
        return Some(Int64(b - b'A') + 1)
    }
    if (b >= b'a' && b <= b'z') {
        return Some(Int64(b - b'a') + 1)
    }
    None
}
