/*
 * XmlParser 单元测试：Characters / CDATA / Comment / PI / DOCTYPE。
 */
package cangjie_xml.parser

import std.unittest.*
import std.collection.*

/* ---------- Characters / CDATA / merging ---------- */

@Test
public func testConsecutiveTextAndRefsMerged(): Unit {
    let evs = events("<a>hi&amp;there&#65;!</a>")
    var count = 0
    var combined = ""
    for (e in evs) {
        match (e) {
            case Characters(_, s) =>
                count += 1
                combined += s
            case _ => ()
        }
    }
    @Expect(count, 1)
    @Expect(combined, "hi&thereA!")
}

@Test
public func testCdataIndependentEvent(): Unit {
    let evs = events("<a>pre<![CDATA[<x>]]>post</a>")
    var seq = ArrayList<String>()
    for (e in evs) {
        match (e) {
            case Characters(_, s) => seq.add("C:${s}")
            case Cdata(_, s) => seq.add("D:${s}")
            case _ => ()
        }
    }
    @Expect(seq.size, 3)
    @Expect(seq[0], "C:pre")
    @Expect(seq[1], "D:<x>")
    @Expect(seq[2], "C:post")
}

@Test
public func testCommentAndPi(): Unit {
    let evs = events("<a><!-- c --><?t d?></a>")
    var sawComment = false
    var sawPi = false
    for (e in evs) {
        match (e) {
            case CommentEvent(_, s) =>
                sawComment = true
                @Expect(s, " c ")
            case Pi(_, t, d) =>
                sawPi = true
                @Expect(t, "t")
                @Expect(d, "d")
            case _ => ()
        }
    }
    @Expect(sawComment, true)
    @Expect(sawPi, true)
}

@Test
public func testDoctypeEvent(): Unit {
    let evs = events("<!DOCTYPE html><html/>")
    var saw = false
    for (e in evs) {
        match (e) {
            case Doctype(_, n) =>
                saw = true
                @Expect(n, "html")
            case _ => ()
        }
    }
    @Expect(saw, true)
}

