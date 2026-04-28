package fastxml

/**
 * CangjieXML 库版本号
 *
 * 遵循 SemVer：`MAJOR.MINOR.PATCH`。当前处于 0.x，公共 API 仍可能演化；
 * 当 DOM / Parser / Writer 三根主梁均稳定后，将发布 1.0.0
 */
public const CANGJIE_XML_VERSION: String = "0.1.0"

/**
 * 返回库的版本字符串
 *
 * 用于运行时探测，便于宿主程序在日志 / 诊断信息中打印库版本
 */
public func cangjieXmlVersion(): String {
    CANGJIE_XML_VERSION
}
