/*
 * parser — 词法器产出的 Token 类型
 *
 * 对应 libxml2：`parser.c` 内部通过回调（`xmlSAX`）直接产出事件，没有显式的 token
 * 流中间层。本项目把词法层独立出来以便：
 *   - 单元可测（Token 流易于断言对比）；
 *   - 容错模式下可以"消费掉"已识别的语法片段后继续；
 *   - 后续 `XmlParser`（Phase 3b）把 Token 流聚合成 `SaxEvent`。
 *
 * Token 的粒度设计目标：
 *   - **属性级**（不把整个 `<a x="1" y="2">` 并成一个 token），因为属性值本身可能
 *     很长甚至含实体引用，粒度越细越利于容错恢复；
 *   - **实体引用** 作为独立 Token（在 Parser 层再展开），这样词法器本身不需要
 *     实体表；
 *   - **Text / CDATA / Comment 的文本体** 一次性给出，而不是逐字符——文本体本身
 *     没有子结构，合并更省事。
 */
package cangjie_xml.parser

import cangjie_xml.core.*

/** 属性值使用的引号。 */
public enum AttrQuote <: Equatable<AttrQuote> & ToString {
    | Single
    | Double

    public operator func ==(that: AttrQuote): Bool {
        match ((this, that)) {
            case (Single, Single) => return true
            case (Double, Double) => return true
            case _ => return false
        }
    }

    public operator func !=(that: AttrQuote): Bool {
        return !(this == that)
    }

    public func toString(): String {
        match (this) {
            case Single => return "'"
            case Double => return "\""
        }
    }
}

/**
 * 词法 Token。每个 Token 携带其 **起始位置**（对应 token 第一个字符的位置）。
 *
 * 约定：
 *   - `name` 字段在 XML 1.0/1.1 的 `Name` 产生式范围内（已由词法器校验），
 *     保留原始前缀形式 `prefix:local`，由 Parser 在组装 QName 时拆分。
 *   - `AttrValue.value` 已经 **去引号**，但 **实体引用 / 字符引用未展开**——它们作为
 *     独立的 `EntityRef` / `CharRef` Token 交织在 `AttrValue` 之间。
 *   - `Text.value` 已经做过换行归一化（由 `RuneReader` 完成），**不**展开实体。
 *   - `CDataSection.value` 为原文（`<![CDATA[...]]>` 之间的原始字符，不归一化）。
 *   - `ProcessingInstruction.data` 可能为空字符串（PI 只有 target）。
 *   - `DoctypeStart` 只给出根元素名；External ID、内部子集解析留给 Parser / DTD 层。
 *   - `Eof` 永远在流末尾出现一次，之后 Lexer 不再返回。
 */
public enum Token <: ToString {
    // XML 声明
    | XmlDeclStart(Position)
    | XmlDeclEnd(Position)
    // 元素起始 `<name`；与属性之间尚未读到结束符
    | ElementOpenStart(Position, String)
    // `<name attrs... />` 的 `/>`
    | ElementSelfClose(Position)
    // `<name attrs...>` 的 `>`
    | ElementOpenEnd(Position)
    // 结束标签 `</name>`（完整匹配）
    | ElementClose(Position, String)
    // 属性名（在 ElementOpenStart 之后、ElementOpenEnd / ElementSelfClose 之前）
    | AttrName(Position, String)
    // `=`（属性等号）
    | AttrEq(Position)
    // 属性值的起始引号
    | AttrValueStart(Position, AttrQuote)
    // 属性值内的字面字符串块（不含引号、不含实体引用）
    | AttrValueChunk(Position, String)
    // 属性值的结束引号
    | AttrValueEnd(Position, AttrQuote)
    // 文本节点内容（已做换行归一化）
    | Text(Position, String)
    // `<![CDATA[...]]>` 的内容（原样）
    | CDataSection(Position, String)
    // `<!-- ... -->` 内容（原样，不含分隔符）
    | Comment(Position, String)
    // `<?target data?>`：target 非 xml/XML（XML 声明走 XmlDeclStart / AttrName / AttrValue* / XmlDeclEnd）
    | ProcessingInstruction(Position, String, String)
    // `<!DOCTYPE rootName`：后续的 ExternalID / internal subset 由 Parser 处理
    | DoctypeStart(Position, String)
    // DOCTYPE 结束的 `>`（在内部子集 `[...]` 之后或直接跟随）
    | DoctypeEnd(Position)
    // `&name;`（预定义实体如 lt/gt/amp/apos/quot 由 Parser 识别）
    | EntityRef(Position, String)
    // `&#N;` / `&#xN;` 数字字符引用（十进制 / 十六进制），已解析为码点
    | CharRef(Position, Int32)
    // 流结束
    | Eof(Position)

    /** Token 起始位置。 */
    public func position(): Position {
        match (this) {
            case XmlDeclStart(p) => return p
            case XmlDeclEnd(p) => return p
            case ElementOpenStart(p, _) => return p
            case ElementSelfClose(p) => return p
            case ElementOpenEnd(p) => return p
            case ElementClose(p, _) => return p
            case AttrName(p, _) => return p
            case AttrEq(p) => return p
            case AttrValueStart(p, _) => return p
            case AttrValueChunk(p, _) => return p
            case AttrValueEnd(p, _) => return p
            case Text(p, _) => return p
            case CDataSection(p, _) => return p
            case Comment(p, _) => return p
            case ProcessingInstruction(p, _, _) => return p
            case DoctypeStart(p, _) => return p
            case DoctypeEnd(p) => return p
            case EntityRef(p, _) => return p
            case CharRef(p, _) => return p
            case Eof(p) => return p
        }
    }

    public func toString(): String {
        match (this) {
            case XmlDeclStart(_) => return "XmlDeclStart"
            case XmlDeclEnd(_) => return "XmlDeclEnd"
            case ElementOpenStart(_, n) => return "ElementOpenStart(${n})"
            case ElementSelfClose(_) => return "ElementSelfClose"
            case ElementOpenEnd(_) => return "ElementOpenEnd"
            case ElementClose(_, n) => return "ElementClose(${n})"
            case AttrName(_, n) => return "AttrName(${n})"
            case AttrEq(_) => return "AttrEq"
            case AttrValueStart(_, q) => return "AttrValueStart(${q})"
            case AttrValueChunk(_, s) => return "AttrValueChunk(${s})"
            case AttrValueEnd(_, q) => return "AttrValueEnd(${q})"
            case Text(_, s) => return "Text(${s})"
            case CDataSection(_, s) => return "CDataSection(${s})"
            case Comment(_, s) => return "Comment(${s})"
            case ProcessingInstruction(_, t, d) => return "PI(${t}, ${d})"
            case DoctypeStart(_, n) => return "DoctypeStart(${n})"
            case DoctypeEnd(_) => return "DoctypeEnd"
            case EntityRef(_, n) => return "EntityRef(${n})"
            case CharRef(_, cp) => return "CharRef(${cp})"
            case Eof(_) => return "Eof"
        }
    }
}
