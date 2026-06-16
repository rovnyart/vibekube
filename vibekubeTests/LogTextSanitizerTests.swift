import Testing
@testable import vibekube

struct LogTextSanitizerTests {
    @Test func stripsANSIEscapeSequences() {
        let text = "\u{001B}[31merror\u{001B}[0m plain \u{001B}[1;32mok\u{001B}[0m"

        let sanitized = LogTextSanitizer.stripANSISequences(from: text)

        #expect(sanitized == "error plain ok")
    }

    @Test func stripsTerminalTitleSequences() {
        let text = "before \u{001B}]0;secret-title\u{0007}after"

        let sanitized = LogTextSanitizer.stripANSISequences(from: text)

        #expect(sanitized == "before after")
    }
}
