/*
 * core — 字符串 intern 池
 *
 * 对应 libxml2: dict.c / hash.c（xmlDict）。
 *
 * 由于仓颉 `String` 不可变 + GC，无需像 libxml2 那样手工引用计数；
 * `NameTable` 仅负责返回"池内规范实例"，同一逻辑字符串多次 intern 返回
 * 同一 `String` 值（`==` 相等且引用可能相同）。
 */
package cangjie_xml.core

import std.collection.*
import std.collection.concurrent.*

/**
 * 基础 intern 池：非线程安全，适用于单解析器实例 / 单 `Document` 作用域。
 * 对并发场景请使用 `ConcurrentNameTable`。
 */
public class NameTable {
    private let table: HashMap<String, String>

    public init() {
        this.table = HashMap<String, String>()
    }

    /** 返回池内规范实例；若不存在则插入。 */
    public func intern(s: String): String {
        match (table.get(s)) {
            case Some(existing) => return existing
            case None =>
                table.add(s, s)
                return s
        }
    }

    /** 仅查询，不插入。 */
    public func interned(s: String): ?String {
        return table.get(s)
    }

    /** 池中字符串数量。 */
    public prop size: Int64 {
        get() {
            return table.size
        }
    }

    public func contains(s: String): Bool {
        return table.contains(s)
    }

    public func clear(): Unit {
        table.clear()
    }
}

/** 线程安全的 intern 池，基于 `ConcurrentHashMap`，可跨线程共享。 */
public class ConcurrentNameTable {
    private let table: ConcurrentHashMap<String, String>

    public init() {
        this.table = ConcurrentHashMap<String, String>()
    }

    public func intern(s: String): String {
        match (table.get(s)) {
            case Some(existing) => return existing
            case None => ()
        }
        // putIfAbsent 语义：若此间被其他线程插入，取其值
        match (table.addIfAbsent(s, s)) {
            case Some(existing) => return existing
            case None => return s
        }
    }

    public func interned(s: String): ?String {
        return table.get(s)
    }

    public func contains(s: String): Bool {
        return table.contains(s)
    }

    public prop size: Int64 {
        get() {
            return table.size
        }
    }
}
