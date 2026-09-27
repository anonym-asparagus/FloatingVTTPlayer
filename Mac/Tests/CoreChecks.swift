import Foundation

@main
enum CoreChecks {
    static func main() throws {
        let vtt = """
        \u{FEFF}WEBVTT

        first cue
        00:01.000 --> 00:03.000
        Hello <b>world</b> &amp; friends<br>again

        00:02.500 --> 00:04.000
        Overlapping cue

        00:05.000 --> 00:04.000
        Invalid timing
        """
        let cues = WebVTTParser.parse(vtt)
        precondition(cues.count == 2, "Expected two valid cues")
        precondition(cues[0].start == 1 && cues[0].end == 3)
        precondition(cues[0].text == "Hello world & friends\nagain")
        precondition(cues[1].start == 2.5)

        let audio = URL(fileURLWithPath: "/tracks/01_Night-Ride.wav")
        let doubleExtension = URL(fileURLWithPath: "/tracks/01_Night-Ride.wav.vtt")
        let punctuation = URL(fileURLWithPath: "/tracks/01 Night Ride.vtt")
        let wrongNumber = URL(fileURLWithPath: "/tracks/02_Night-Ride.vtt")
        precondition(SubtitleMatcher.findBestMatch(for: audio,
            in: [punctuation, doubleExtension, wrongNumber], excluding: []) == doubleExtension)
        precondition(SubtitleMatcher.findBestMatch(for: audio,
            in: [punctuation, doubleExtension, wrongNumber], excluding: [doubleExtension]) == punctuation)
        precondition(SubtitleMatcher.score(audio: audio, subtitle: wrongNumber) < 0)

        let tracks = [
            AudioTrack(audioURL: URL(fileURLWithPath: "/library/Night Ride.wav"), subtitleURL: nil),
            AudioTrack(audioURL: URL(fileURLWithPath: "/library/Quiet Morning.mp3"), subtitleURL: nil),
            AudioTrack(audioURL: URL(fileURLWithPath: "/library/Sunset Walk.wav"), subtitleURL: nil)
        ]
        precondition(FilenameSearch.rank(tracks, matching: "night ride").map(\.fileName) == ["Night Ride.wav"])
        precondition(FilenameSearch.rank(tracks, matching: "nigt ride").map(\.fileName) == ["Night Ride.wav"])
        precondition(FilenameSearch.rank(tracks, matching: "sset wlk").map(\.fileName) == ["Sunset Walk.wav"])
        precondition(FilenameSearch.rank(tracks, matching: "nothing like this").isEmpty)
        print("Core checks passed")
    }
}
