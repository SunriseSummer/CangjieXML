package cangjie_xml.dom

/**
 * DOM 包内常量集中定义点——避免魔鬼字符串散落到多处。
 *
 * 注意：此常量是"XML 声明内部 payload"的字面量（不含外层 `<? ... ?>`），
 * 与 `XmlDeclaration.value` 的语义一致。Writer 包里另有一份供其合成默认声明
 * 使用的同值常量，二者保持独立以避免 `writer → dom → writer` 的循环依赖。
 */
public const DEFAULT_DECLARATION_VALUE: String = "xml version=\"1.0\" encoding=\"UTF-8\""
