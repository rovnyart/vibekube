import Testing
@testable import vibekube

struct LogJSONLFormatterTests {
    @Test func formatsCompactJSONObjects() {
        let line = #"{"level":"info","count":3,"ok":true,"nested":{"service":"api"}}"#

        let formatted = LogJSONLFormatter.formatLine(line)

        #expect(formatted.contains(#""count" : 3"#))
        #expect(formatted.contains(#""level" : "info""#))
        #expect(formatted.contains(#""nested" : {"#))
    }

    @Test func preservesKubernetesTimestampPrefix() {
        let line = #"2026-06-16T16:20:00.123456789Z {"message":"hello","pod":"counter-0"}"#

        let formatted = LogJSONLFormatter.formatLine(line)

        #expect(formatted.hasPrefix(#"2026-06-16T16:20:00.123456789Z {"#))
        #expect(formatted.contains(#""message" : "hello""#))
        #expect(formatted.contains(#""pod" : "counter-0""#))
    }

    @Test func leavesNonJSONLinesUntouched() {
        let line = "2026-06-16T16:20:00Z plain text log line"

        #expect(LogJSONLFormatter.formatLine(line) == line)
    }

    @Test func leavesInvalidJSONLinesUntouched() {
        let line = #"{"level":"info""#

        #expect(LogJSONLFormatter.formatLine(line) == line)
    }
}
