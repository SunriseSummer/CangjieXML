/*
 * parser — EntityResolver 接口与默认实现
 *
 * 对应 libxml2: `xmlSetExternalEntityLoader` + 内置实体表。
 *
 * 差异（`DESIGN.md §7.4` / `§19`）：
 *   - libxml2 的 `xmlSetExternalEntityLoader` 是全局 hook；CangjieXML 通过
 *     `ParserOptions.entityResolver` 显式注入，无隐式全局状态。
 *   - 默认**拒绝**外部实体（XXE 防护，`DESIGN.md §15`）。本迭代（Phase 3b）仅
 *     实现预定义实体（`lt / gt / amp / apos / quot`）+ 字符引用；加载外部实体
 *     的完整 `IoSource` 接入留待 Phase 3c。
 */
package cangjie_xml.parser

import cangjie_xml.io.*

/**
 * 已解析的实体展开结果。
 *
 * - `Text(s)`：展开为字面字符串（最常见，预定义实体走此分支）；
 * - `External(source, publicId, systemId)`：外部解析实体，parser 会把 `source`
 *   当作一段子输入递归解析（Phase 3c 接入）。当前版本 `DefaultEntityResolver`
 *   不会返回此分支。
 */
public enum EntityResolution {
    | Text(String)
    | External(IoSource, ?String, ?String)
}

/**
 * 实体解析接口。
 *
 * 实现方必须是线程安全的不可变对象（本库鼓励纯函数式用法）。
 *
 * 契约：
 *   - `resolveEntity(name)`：返回 `Some(...)` 表示已知实体；`None` 表示未知。
 *     parser 会在未知时：
 *       * `substituteEntities && !recover` → 抛 `XmlException(Malformed)`；
 *       * `!substituteEntities` → 原样产出 `SaxEvent.EntityReference(name)`；
 *       * `recover` → 产出 `SaxEvent.ParseError(..)` 并跳过（Phase 3c）。
 */
public interface EntityResolver {
    func resolveEntity(name: String): ?EntityResolution
}

/**
 * 默认实体解析器。
 *
 * 仅识别 XML 预定义的 5 个实体：
 *   `lt` → `<`,  `gt` → `>`,  `amp` → `&`,  `apos` → `'`,  `quot` → `"`
 *
 * 其他命名实体一律返回 `None`。外部实体永不加载。
 *
 * 通过 `withAdditional(entities)` 可基于默认派生出含用户实体的解析器——语义为
 * "预定义实体 + 用户字典"；用户**不得**覆盖预定义实体的含义（XML §4.6）。
 */
public class DefaultEntityResolver <: EntityResolver {
    public DefaultEntityResolver() {}

    public func resolveEntity(name: String): ?EntityResolution {
        match (name) {
            case "lt" => return Some(EntityResolution.Text("<"))
            case "gt" => return Some(EntityResolution.Text(">"))
            case "amp" => return Some(EntityResolution.Text("&"))
            case "apos" => return Some(EntityResolution.Text("'"))
            case "quot" => return Some(EntityResolution.Text("\""))
            case _ => return None
        }
    }
}

/**
 * 派生解析器：预定义实体 + 用户提供的额外命名实体映射。用于 DTD 内部子集
 * 的模拟 / 测试便利。
 */
public class MapEntityResolver <: EntityResolver {
    private let base: EntityResolver
    private let extra: Array<(String, String)>

    public init(extra: Array<(String, String)>, base!: EntityResolver = DefaultEntityResolver()) {
        this.base = base
        this.extra = extra
    }

    public func resolveEntity(name: String): ?EntityResolution {
        // 预定义优先
        match (base.resolveEntity(name)) {
            case Some(r) => return Some(r)
            case None => ()
        }
        for ((k, v) in extra) {
            if (k == name) {
                return Some(EntityResolution.Text(v))
            }
        }
        return None
    }
}
