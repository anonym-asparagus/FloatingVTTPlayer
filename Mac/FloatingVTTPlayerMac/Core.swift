import Foundation

struct SubtitleCue: Equatable {
    let start: TimeInterval
    let end: TimeInterval
    let text: String
}

struct AudioTrack: Identifiable, Equatable {
    let audioURL: URL
    let subtitleURL: URL?

    var id: URL { audioURL }
    var fileName: String { audioURL.lastPathComponent }
    var hasSubtitle: Bool { subtitleURL != nil }
}

enum WebVTTParser {
    private static let timing = try! NSRegularExpression(
        pattern: #"^(?:(?:\d{2,}):)?\d{2}:\d{2}[.,]\d{3}\s*-->\s*(?:(?:\d{2,}):)?\d{2}:\d{2}[.,]\d{3}(?:\s+.*)?$"#
    )
    private static let timestamps = try! NSRegularExpression(
        pattern: #"^(?<start>(?:(?:\d{2,}):)?\d{2}:\d{2}[.,]\d{3})\s*-->\s*(?<end>(?:(?:\d{2,}):)?\d{2}:\d{2}[.,]\d{3})(?:\s+.*)?$"#
    )
    private static let breaks = try! NSRegularExpression(pattern: #"<br\s*/?>"#, options: .caseInsensitive)
    private static let tags = try! NSRegularExpression(pattern: #"<[^>]+>"#)
    private static let entities = try! NSRegularExpression(pattern: #"&(#(?:x[0-9a-fA-F]+|[0-9]+)|[a-zA-Z]+);"#)

    static func parseFile(at url: URL) throws -> [SubtitleCue] {
        try parse(String(contentsOf: url, encoding: .utf8))
    }

    static func parse(_ content: String) -> [SubtitleCue] {
        let normalized = String(content.drop(while: { $0 == "\u{FEFF}" }))
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let blocks = normalized.replacingOccurrences(
            of: #"\n[\t ]*\n"#, with: "\u{0000}", options: .regularExpression
        ).components(separatedBy: "\u{0000}")

        return blocks.compactMap { block in
            let lines = block.components(separatedBy: "\n")
            guard let index = lines.firstIndex(where: { candidate in
                let line = candidate.trimmingCharacters(in: .whitespaces)
                return timing.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
            }) else {
                return nil
            }
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            let range = NSRange(line.startIndex..., in: line)
            guard let match = timestamps.firstMatch(in: line, range: range),
                  let startRange = Range(match.range(withName: "start"), in: line),
                  let endRange = Range(match.range(withName: "end"), in: line),
                  let start = parseTimestamp(String(line[startRange])),
                  let end = parseTimestamp(String(line[endRange])), end > start else {
                return nil
            }
            let raw = lines.dropFirst(index + 1).joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { return nil }
            let withBreaks = breaks.stringByReplacingMatches(
                in: raw, range: NSRange(raw.startIndex..., in: raw), withTemplate: "\n"
            )
            let plain = tags.stringByReplacingMatches(
                in: withBreaks, range: NSRange(withBreaks.startIndex..., in: withBreaks), withTemplate: ""
            )
            return SubtitleCue(start: start, end: end,
                               text: decodeEntities(plain).trimmingCharacters(in: .whitespacesAndNewlines))
        }.sorted { $0.start < $1.start }
    }

    private static func parseTimestamp(_ value: String) -> TimeInterval? {
        let parts = value.replacingOccurrences(of: ",", with: ".").split(separator: ":")
        guard parts.count == 2 || parts.count == 3,
              let seconds = Double(parts.last!),
              let minutes = Double(parts[parts.count - 2]) else { return nil }
        let hours = parts.count == 3 ? Double(parts[0]) : 0
        guard let hours else { return nil }
        return hours * 3600 + minutes * 60 + seconds
    }

    private static func decodeEntities(_ input: String) -> String {
        let named: [String: String] = [
            "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}",
            "lrm": "\u{200E}", "rlm": "\u{200F}", "copy": "©", "reg": "®", "mdash": "—", "ndash": "–"
        ]
        var result = input
        for match in entities.matches(in: input, range: NSRange(input.startIndex..., in: input)).reversed() {
            guard let fullRange = Range(match.range, in: result),
                  let valueRange = Range(match.range(at: 1), in: result) else { continue }
            let value = String(result[valueRange])
            let decoded: String?
            if value.hasPrefix("#") {
                let hex = value.hasPrefix("#x") || value.hasPrefix("#X")
                let digits = value.dropFirst(hex ? 2 : 1)
                decoded = UInt32(digits, radix: hex ? 16 : 10).flatMap(Unicode.Scalar.init).map(String.init)
            } else {
                decoded = named[value]
            }
            if let decoded { result.replaceSubrange(fullRange, with: decoded) }
        }
        return result
    }
}

enum SubtitleMatcher {
    private static let knownExtensions: Set<String> = ["vtt", "wav", "wave", "mp3"]
    private static let numberRegex = try! NSRegularExpression(pattern: #"\d+"#)

    static func findBestMatch(for audio: URL, in subtitles: [URL], excluding used: Set<URL>) -> URL? {
        subtitles.filter { !used.contains($0) }
            .compactMap { subtitle -> (URL, Double)? in
                let value = score(audio: audio, subtitle: subtitle)
                return value >= 0 ? (subtitle, value) : nil
            }
            .sorted {
                if $0.1 != $1.1 { return $0.1 > $1.1 }
                return $0.0.lastPathComponent.localizedCaseInsensitiveCompare($1.0.lastPathComponent) == .orderedAscending
            }
            .first?.0
    }

    static func score(audio: URL, subtitle: URL) -> Double {
        let audioName = audio.lastPathComponent
        let subtitleName = subtitle.lastPathComponent
        let subtitleWithoutVTT = (subtitleName as NSString).deletingPathExtension
        if subtitleWithoutVTT.caseInsensitiveCompare(audioName) == .orderedSame { return 100_000 }

        let audioCore = stripKnownExtensions(audioName)
        let subtitleCore = stripKnownExtensions(subtitleName)
        if audioCore.caseInsensitiveCompare(subtitleCore) == .orderedSame { return 98_000 }

        let normalizedAudio = normalize(audioCore)
        let normalizedSubtitle = normalize(subtitleCore)
        guard !normalizedAudio.isEmpty, !normalizedSubtitle.isEmpty else { return -1 }
        if normalizedAudio == normalizedSubtitle { return 96_000 }

        let audioNumbers = extractNumbers(audioCore)
        let subtitleNumbers = extractNumbers(subtitleCore)
        let similarity = similarity(normalizedAudio, normalizedSubtitle)
        if !audioNumbers.isEmpty && !subtitleNumbers.isEmpty {
            if audioNumbers == subtitleNumbers { return 90_000 + similarity * 5_000 }
            if audioNumbers[0] == subtitleNumbers[0] { return 85_000 + similarity * 5_000 }
            return -1
        }
        return similarity >= 0.78 ? 60_000 + similarity * 10_000 : -1
    }

    private static func stripKnownExtensions(_ filename: String) -> String {
        var result = filename
        while knownExtensions.contains((result as NSString).pathExtension.lowercased()) {
            result = (result as NSString).deletingPathExtension
        }
        return result
    }

    private static func normalize(_ value: String) -> String {
        value.precomposedStringWithCompatibilityMapping.lowercased()
            .unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init).joined()
    }

    private static func extractNumbers(_ value: String) -> [String] {
        let normalized = value.precomposedStringWithCompatibilityMapping
        return numberRegex.matches(in: normalized, range: NSRange(normalized.startIndex..., in: normalized))
            .compactMap { Range($0.range, in: normalized).map { String(normalized[$0]) } }
            .map { number in
                let digits = number.compactMap(\.wholeNumberValue).map(String.init).joined()
                let trimmed = digits.drop(while: { $0 == "0" })
                return trimmed.isEmpty ? "0" : String(trimmed)
            }
    }

    private static func similarity(_ left: String, _ right: String) -> Double {
        let a = Array(left), b = Array(right)
        guard !a.isEmpty || !b.isEmpty else { return 1 }
        var previous = Array(0...a.count)
        for (row, rightCharacter) in b.enumerated() {
            var current = Array(repeating: 0, count: a.count + 1)
            current[0] = row + 1
            for (column, leftCharacter) in a.enumerated() {
                current[column + 1] = min(current[column] + 1, previous[column + 1] + 1,
                                          previous[column] + (leftCharacter == rightCharacter ? 0 : 1))
            }
            previous = current
        }
        return 1 - Double(previous[a.count]) / Double(max(a.count, b.count))
    }
}

enum FilenameSearch {
    static func rank(_ tracks: [AudioTrack], matching query: String) -> [AudioTrack] {
        let needle = normalize(query)
        guard !needle.isEmpty else { return tracks }
        return tracks.compactMap { track -> (AudioTrack, Int)? in
            guard let score = score(filename: track.fileName, needle: needle) else { return nil }
            return (track, score)
        }
        .sorted {
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            return $0.0.fileName.localizedStandardCompare($1.0.fileName) == .orderedAscending
        }
        .map(\.0)
    }

    private static func score(filename: String, needle: String) -> Int? {
        let stem = (filename as NSString).deletingPathExtension
        let normalized = normalize(stem)
        if normalized == needle { return 1_000 }
        if normalized.hasPrefix(needle) { return 900 - (normalized.count - needle.count) }
        if normalized.contains(needle) { return 800 - (normalized.count - needle.count) }

        let tokens = stem.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map(normalize).filter { !$0.isEmpty }
        let distances = ([normalized] + tokens).map { editDistance(needle, $0) }
        if let closest = distances.min(), closest <= max(1, needle.count / 4) {
            return 600 - closest * 40
        }
        let characters = Array(normalized)
        var cursor = 0
        for character in needle {
            guard let offset = characters[cursor...].firstIndex(of: character) else { return nil }
            cursor = offset + 1
        }
        return 400 - (characters.count - needle.count)
    }

    private static func normalize(_ value: String) -> String {
        value.precomposedStringWithCompatibilityMapping.lowercased()
            .unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init).joined()
    }

    private static func editDistance(_ left: String, _ right: String) -> Int {
        let a = Array(left), b = Array(right)
        var previous = Array(0...b.count)
        for (row, leftCharacter) in a.enumerated() {
            var current = Array(repeating: 0, count: b.count + 1)
            current[0] = row + 1
            for (column, rightCharacter) in b.enumerated() {
                current[column + 1] = min(current[column] + 1, previous[column + 1] + 1,
                                          previous[column] + (leftCharacter == rightCharacter ? 0 : 1))
            }
            previous = current
        }
        return previous[b.count]
    }
}
