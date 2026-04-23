/*
 * core — 错误模型
 *
 * 对应 libxml2: error.c 的 xmlError、xmlErrorLevel、xmlParserError 等。
 *
 * 设计原则：
 *  - 用 `enum XmlError` 表达错误种类，利于 `match` 编译期穷尽；
 *  - 用 `class XmlException <: Exception` 作为抛出载体，使内部 `Result` 与外部
 *    异常 API 自由切换；
 *  - `Position` 记录源码定位（行 / 列 / 字节偏移），贯穿解析器 / 验证器 / 序列化器；
 *  - `ErrorCollector` 接口使下游可在不抛异常的前提下收集全部诊断。
 */
package cangjie_xml.core

import std.collection.*

/**
 * 源码位置。`line` / `column` 从 1 开始；`byteOffset` 从 0 开始；
 * 对"位置不可知"的场景使用 `Position.unknown()`。
 */
public struct Position <: Equatable<Position> & ToString {
    public let source: ?String
    public let line: Int32
    public let column: Int32
    public let byteOffset: Int64

    public init(source!: ?String, line!: Int32, column!: Int32, byteOffset!: Int64) {
        this.source = source
        this.line = line
        this.column = column
        this.byteOffset = byteOffset
    }

    public static func unknown(): Position {
        return Position(source: None, line: 0, column: 0, byteOffset: -1)
    }

    public func isKnown(): Bool {
        return line > 0 && column > 0
    }

    public operator func ==(that: Position): Bool {
        return this.source == that.source && this.line == that.line && this.column == that.column && this.byteOffset == that
            .byteOffset
    }

    public operator func !=(that: Position): Bool {
        return !(this == that)
    }

    public func toString(): String {
        let srcStr = match (source) {
            case Some(s) => s
            case None => "<input>"
        }
        if (!isKnown()) {
            return "${srcStr}:?:?"
        }
        return "${srcStr}:${line}:${column}"
    }
}

/** 诊断级别。 */
public enum Severity <: ToString {
    | Warning
    | Error
    | Fatal

    public func toString(): String {
        match (this) {
            case Warning => "warning"
            case Error => "error"
            case Fatal => "fatal"
        }
    }
}

/**
 * XML 错误种类。每个分支携带定位信息与必要的上下文参数。
 *
 * 分类受 libxml2 `xmlParserErrors` 启发，但去除大量 C 专属细节错误，
 * 归并为更少的语义类别，保留最有用的位置 / 上下文信息。
 */
public enum XmlError <: ToString {
    /** 非良构：一般语法错误。 */
    | Malformed(Position, String)
    /** 非良构：意外 EOF。 */
    | UnexpectedEof(Position, String)
    /** 非良构：意外字符。 */
    | UnexpectedChar(Position, Rune, String)
    /** 编码错误：非法字节序列或不支持的编码名。 */
    | EncodingError(Position, String)
    /** URI 解析错误。 */
    | UriError(String)
    /** 命名空间错误：未定义前缀、空前缀等。 */
    | NamespaceError(Position, String)
    /** 验证失败：DTD / XSD / RelaxNG。 */
    | ValidationError(Position, String)
    /** 资源限制：深度 / 实体展开 / 缓冲上限。 */
    | LimitExceeded(Position, String)
    /** 输入 / 输出失败。 */
    | IoError(String)
    /** 其他：不在上述类别中的错误。 */
    | Other(Position, String)

    /** 获取诊断位置。对于与位置无关的错误（如 UriError、IoError）返回 unknown。 */
    public func position(): Position {
        match (this) {
            case Malformed(p, _) => p
            case UnexpectedEof(p, _) => p
            case UnexpectedChar(p, _, _) => p
            case EncodingError(p, _) => p
            case UriError(_) => Position.unknown()
            case NamespaceError(p, _) => p
            case ValidationError(p, _) => p
            case LimitExceeded(p, _) => p
            case IoError(_) => Position.unknown()
            case Other(p, _) => p
        }
    }

    /** 人类可读的简短错误描述（不含位置）。 */
    public func message(): String {
        match (this) {
            case Malformed(_, m) => "malformed: ${m}"
            case UnexpectedEof(_, m) => "unexpected EOF: ${m}"
            case UnexpectedChar(_, r, m) => "unexpected character '${r}': ${m}"
            case EncodingError(_, m) => "encoding error: ${m}"
            case UriError(m) => "URI error: ${m}"
            case NamespaceError(_, m) => "namespace error: ${m}"
            case ValidationError(_, m) => "validation error: ${m}"
            case LimitExceeded(_, m) => "limit exceeded: ${m}"
            case IoError(m) => "I/O error: ${m}"
            case Other(_, m) => m
        }
    }

    /** 默认诊断级别：`UnexpectedEof` / `Malformed` 等为 `Fatal`，其余为 `Error`。 */
    public func defaultSeverity(): Severity {
        match (this) {
            case Malformed(_, _) => Severity.Fatal
            case UnexpectedEof(_, _) => Severity.Fatal
            case UnexpectedChar(_, _, _) => Severity.Fatal
            case EncodingError(_, _) => Severity.Fatal
            case LimitExceeded(_, _) => Severity.Fatal
            case _ => Severity.Error
        }
    }

    public func toString(): String {
        return "${position()}: ${defaultSeverity()}: ${message()}"
    }
}

/** XML 异常：抛给上层的通用载体。 */
public class XmlException <: Exception {
    public let error: XmlError

    public init(error: XmlError) {
        super(error.toString())
        this.error = error
    }
}

/** 诊断收集器：解析器容错模式下的默认目的地。 */
public interface ErrorCollector {
    func report(severity: Severity, error: XmlError): Unit
}

/** 默认实现：把诊断追加到 `ArrayList`，供调用方事后读取。 */
public class ListErrorCollector <: ErrorCollector {
    private let items: ArrayList<(Severity, XmlError)>

    public init() {
        this.items = ArrayList<(Severity, XmlError)>()
    }

    public func report(severity: Severity, error: XmlError): Unit {
        items.add((severity, error))
    }

    /** 到目前为止收集到的全部诊断。 */
    public func entries(): Array<(Severity, XmlError)> {
        let out = Array<(Severity, XmlError)>(items.size, repeat: (Severity.Error, XmlError.Other(Position.unknown(), "")))
        for (i in 0..items.size) {
            out[i] = items[i]
        }
        return out
    }

    public func isEmpty(): Bool {
        return items.isEmpty()
    }

    public func size(): Int64 {
        return items.size
    }

    public func hasFatal(): Bool {
        for (i in 0..items.size) {
            let (sev, _) = items[i]
            match (sev) {
                case Fatal => return true
                case _ => ()
            }
        }
        return false
    }
}

/** 丢弃全部诊断；用于 best-effort 解析场景。 */
public class SilentErrorCollector <: ErrorCollector {
    public func report(severity: Severity, error: XmlError): Unit {
        let _ = severity
        let _ = error
    }
}
