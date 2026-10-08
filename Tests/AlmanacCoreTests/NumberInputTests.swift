import Testing
@testable import AlmanacCore

@Suite("Number input in either language")
struct NumberInputTests {
    @Test("ASCII input parses as it always did")
    func ascii() {
        #expect(Double(userInput: "72.5") == 72.5)
        #expect(Double(userInput: "  250 ") == 250)
        #expect(Int(userInput: "8") == 8)
        #expect(Double(userInput: "") == nil)
        #expect(Double(userInput: "72abc") == nil)
        #expect(Int(userInput: "7.5") == nil)
    }

    @Test("Arabic-Indic digits and the Arabic decimal separator parse")
    func arabicIndic() {
        #expect(Double(userInput: "٧٢٫٥") == 72.5)
        #expect(Int(userInput: "١٠") == 10)
        #expect(Double(userInput: "٢٥٠") == 250)
    }

    @Test("Persian digits parse")
    func persian() {
        #expect(Int(userInput: "۱۲") == 12)
    }

    @Test("The thousands separator and direction marks are ignored")
    func separatorsAndMarks() {
        #expect(Int(userInput: "١٬٢٠٠") == 1200)
        #expect(Double(userInput: "\u{200F}٧٢\u{061C}") == 72)
    }

    @Test("Arabic letters are still refused")
    func letters() {
        #expect(Double(userInput: "سبعون") == nil)
    }
}
