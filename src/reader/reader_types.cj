/*
 * reader — ReaderNodeType / ReaderState
 *
 * 对应 .NET `XmlNodeType` / libxml2 `xmlReaderTypes`。CangjieXML 只暴露本项目
 * 真实产出的节点类型，避免 libxml2 20+ 枚举的历史噪音。
 */
package cangjie_xml.reader

public enum ReaderNodeType <: Equatable<ReaderNodeType> & ToString {
    | None
    | XmlDeclaration
    | Doctype
    | Element
    | EndElement
    | Attribute
    | Text
    | Cdata
    | Comment
    | Pi
    | EntityReference
    | Whitespace
    | EndDocument

    public operator func ==(that: ReaderNodeType): Bool {
        match ((this, that)) {
            case (None, None) => true
            case (XmlDeclaration, XmlDeclaration) => true
            case (Doctype, Doctype) => true
            case (Element, Element) => true
            case (EndElement, EndElement) => true
            case (Attribute, Attribute) => true
            case (Text, Text) => true
            case (Cdata, Cdata) => true
            case (Comment, Comment) => true
            case (Pi, Pi) => true
            case (EntityReference, EntityReference) => true
            case (Whitespace, Whitespace) => true
            case (EndDocument, EndDocument) => true
            case _ => false
        }
    }

    public operator func !=(that: ReaderNodeType): Bool {
        return !(this == that)
    }

    public func toString(): String {
        match (this) {
            case None => return "None"
            case XmlDeclaration => return "XmlDeclaration"
            case Doctype => return "Doctype"
            case Element => return "Element"
            case EndElement => return "EndElement"
            case Attribute => return "Attribute"
            case Text => return "Text"
            case Cdata => return "Cdata"
            case Comment => return "Comment"
            case Pi => return "Pi"
            case EntityReference => return "EntityReference"
            case Whitespace => return "Whitespace"
            case EndDocument => return "EndDocument"
        }
    }
}

/**
 * XmlReader 生命周期状态：
 *   Initial：尚未 `read()`；
 *   Interactive：正常读节点中；
 *   EndOfFile：已到尾；
 *   Error：parser 或校验错误，后续 `read()` 拒绝前进；
 *   Closed：`close()` 被调用。
 */
public enum ReaderState <: Equatable<ReaderState> & ToString {
    | Initial
    | Interactive
    | EndOfFile
    | Error
    | Closed

    public operator func ==(that: ReaderState): Bool {
        match ((this, that)) {
            case (Initial, Initial) => true
            case (Interactive, Interactive) => true
            case (EndOfFile, EndOfFile) => true
            case (Error, Error) => true
            case (Closed, Closed) => true
            case _ => false
        }
    }

    public operator func !=(that: ReaderState): Bool {
        return !(this == that)
    }

    public func toString(): String {
        match (this) {
            case Initial => return "Initial"
            case Interactive => return "Interactive"
            case EndOfFile => return "EndOfFile"
            case Error => return "Error"
            case Closed => return "Closed"
        }
    }
}
