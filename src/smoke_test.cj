package fastxml

import std.unittest.*
import std.unittest.testmacro.*

@Test
func testVersionExposed(): Unit {
    @Assert(CANGJIE_XML_VERSION.size > 0)
    @Assert(cangjieXmlVersion().size > 0)
    @Expect(cangjieXmlVersion(), CANGJIE_XML_VERSION)
}
