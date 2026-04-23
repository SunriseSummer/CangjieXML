/*
 * parser — ASCII / Unicode 字符码点与词法相关数值常量
 *
 * 本项目禁止在代码中散布魔鬼数字（例如 `0x3C` 表示 `<`、`0x10FFFF` 表示 Unicode
 * 上界）。此文件集中定义词法器 / 解析器所需的全部字符码点与数值常量，所有出现点
 * 都应引用这些命名常量。
 *
 * 命名约定：
 *   - `CHAR_xxx` —— 单个 ASCII 字符的 Unicode 码点（`Int32` 与 `Int32(UInt32(Rune))`
 *     的返回类型对齐，便于与 `cp(r)` 直接比较）。
 *   - `xxx_CODEPOINT` —— 非 ASCII 的 XML 相关码点（NEL、LINE SEPARATOR）。
 *   - `HEX_BASE` / `DEC_BASE` / `HEX_DIGIT_OFFSET` —— 字符引用数位换算用数值。
 *   - `UNICODE_MAX_CODEPOINT` —— Unicode 标量值上界 U+10FFFF。
 */
package cangjie_xml.parser

/* ---------- 空白 / 换行 ---------- */

/** Horizontal Tab `\t`，U+0009。 */
const CHAR_HT: Int32 = 0x09
/** Line Feed `\n`，U+000A。 */
const CHAR_LF: Int32 = 0x0A
/** Carriage Return `\r`，U+000D。 */
const CHAR_CR: Int32 = 0x0D
/** 普通空格 `' '`，U+0020。 */
const CHAR_SPACE: Int32 = 0x20

/* ---------- XML 语法相关符号 ---------- */

/** `!`，U+0021，用于 `<!--` / `<![CDATA[` / `<!DOCTYPE`。 */
const CHAR_BANG: Int32 = 0x21
/** `"`，U+0022，属性值双引号。 */
const CHAR_QUOTE: Int32 = 0x22
/** `#`，U+0023，字符引用 `&#...;` 中的分隔符。 */
const CHAR_HASH: Int32 = 0x23
/** `&`，U+0026，实体 / 字符引用起始。 */
const CHAR_AMP: Int32 = 0x26
/** `'`，U+0027，属性值单引号。 */
const CHAR_APOS: Int32 = 0x27
/** `-`，U+002D，注释 `<!-- -->` 分隔符。 */
const CHAR_MINUS: Int32 = 0x2D
/** `.`，U+002E，encoding 名合法字符。 */
const CHAR_DOT: Int32 = 0x2E
/** `/`，U+002F，结束标签 `</...>` / 自闭合 `/>` 前导符。 */
const CHAR_SLASH: Int32 = 0x2F
/** `;`，U+003B，引用结束符。 */
const CHAR_SEMI: Int32 = 0x3B
/** `:`，U+003A，QName 前缀 / 本地名分隔符。 */
const CHAR_COLON: Int32 = 0x3A
/** `<`，U+003C，标签起始。 */
const CHAR_LT: Int32 = 0x3C
/** `=`，U+003D，属性名 = 值。 */
const CHAR_EQ: Int32 = 0x3D
/** `>`，U+003E，标签结束。 */
const CHAR_GT: Int32 = 0x3E
/** `?`，U+003F，处理指令 / XML 声明分隔符。 */
const CHAR_QMARK: Int32 = 0x3F
/** `[`，U+005B，DOCTYPE 内部子集起始。 */
const CHAR_LBRACKET: Int32 = 0x5B
/** `]`，U+005D，DOCTYPE 内部子集结束 / `]]>` CDATA 结束。 */
const CHAR_RBRACKET: Int32 = 0x5D

/* ---------- 数位 / 字母区间（字符引用解码） ---------- */

/** ASCII 数字 `'0'`，U+0030。 */
const CHAR_DIGIT_0: Int32 = 0x30
/** ASCII 数字 `'9'`，U+0039。 */
const CHAR_DIGIT_9: Int32 = 0x39
/** ASCII 大写字母 `'A'`，U+0041。 */
const CHAR_UPPER_A: Int32 = 0x41
/** ASCII 大写字母 `'F'`，U+0046。 */
const CHAR_UPPER_F: Int32 = 0x46
/** ASCII 大写字母 `'Z'`，U+005A。 */
const CHAR_UPPER_Z: Int32 = 0x5A
/** `_`，U+005F，encoding 名 / Name 合法字符。 */
const CHAR_UNDERSCORE: Int32 = 0x5F
/** ASCII 小写字母 `'a'`，U+0061。 */
const CHAR_LOWER_A: Int32 = 0x61
/** ASCII 小写字母 `'f'`，U+0066。 */
const CHAR_LOWER_F: Int32 = 0x66
/** ASCII 小写字母 `'x'`，U+0078，16 进制字符引用 `&#x...;` 标记。 */
const CHAR_LOWER_X: Int32 = 0x78
/** ASCII 小写字母 `'z'`，U+007A。 */
const CHAR_LOWER_Z: Int32 = 0x7A

/* ---------- XML 1.1 专属换行字符 ---------- */

/** NEL 行分隔符，U+0085；XML 1.1 视作换行。 */
const NEL_CODEPOINT: Int32 = 0x85
/** LINE SEPARATOR，U+2028；XML 1.1 视作换行。 */
const LINE_SEPARATOR_CODEPOINT: Int32 = 0x2028

/** `classifyNsDecl` 中 `"xmlns:"` 前缀长度（6 个 ASCII 字节）。 */
const XMLNS_COLON_PREFIX_LEN: Int64 = 6

/** `m`，U+006D。 */
const CHAR_LOWER_M: Int32 = 0x6D
/** `l`，U+006C。 */
const CHAR_LOWER_L: Int32 = 0x6C
/** `n`，U+006E。 */
const CHAR_LOWER_N: Int32 = 0x6E
/** `s`，U+0073。 */
const CHAR_LOWER_S: Int32 = 0x73

/* ---------- UTF-8 编码尺寸界限（用于 O(1) 计算一个 rune 的字节长度） ---------- */

/** UTF-8 单字节 ASCII 上界（不含），`< U+0080` 为 1 字节。 */
const UTF8_1BYTE_UPPER: UInt32 = 0x80u32
/** UTF-8 双字节序列上界（不含），`U+0080..U+07FF` 为 2 字节。 */
const UTF8_2BYTE_UPPER: UInt32 = 0x800u32
/** UTF-8 三字节序列上界（不含），`U+0800..U+FFFF`（扣除代理） 为 3 字节。 */
const UTF8_3BYTE_UPPER: UInt32 = 0x10000u32

/* ---------- 字符引用数位换算 ---------- */

/** Unicode 标量值上界（含）。大于此值的字符引用为非法。 */
const UNICODE_MAX_CODEPOINT: Int64 = 0x10FFFF

/** 十进制基数。 */
const DEC_BASE: Int64 = 10
/** 十六进制基数。 */
const HEX_BASE: Int64 = 16
/** 十六进制字母 `A-F` / `a-f` 代表的数位偏移（相对 `'A'` 或 `'a'`）。 */
const HEX_DIGIT_OFFSET: Int64 = 10
