using System.Net;
using System.Text.RegularExpressions;
using FloatingVttPlayer.Models;

namespace FloatingVttPlayer.Services;

public static partial class WebVttParser
{
    [GeneratedRegex(@"^(?<start>(?:\d{2,}:)?\d{2}:\d{2}[\.,]\d{3})\s*-->\s*(?<end>(?:\d{2,}:)?\d{2}:\d{2}[\.,]\d{3})(?:\s+.*)?$")]
    private static partial Regex TimingRegex();

    [GeneratedRegex(@"<br\s*/?>", RegexOptions.IgnoreCase)]
    private static partial Regex BreakRegex();

    [GeneratedRegex(@"<[^>]+>")]
    private static partial Regex TagRegex();

    public static IReadOnlyList<SubtitleCue> ParseFile(string path)
    {
        var content = File.ReadAllText(path)
            .TrimStart('\uFEFF')
            .Replace("\r\n", "\n")
            .Replace('\r', '\n');

        var blocks = Regex.Split(content, @"\n[\t ]*\n");
        var cues = new List<SubtitleCue>();

        foreach (var block in blocks)
        {
            var lines = block.Split('\n');
            var timingIndex = Array.FindIndex(lines, line => TimingRegex().IsMatch(line.Trim()));
            if (timingIndex < 0)
            {
                continue;
            }

            var match = TimingRegex().Match(lines[timingIndex].Trim());
            if (!TryParseTimestamp(match.Groups["start"].Value, out var start) ||
                !TryParseTimestamp(match.Groups["end"].Value, out var end) ||
                end <= start)
            {
                continue;
            }

            var rawText = string.Join('\n', lines.Skip(timingIndex + 1)).Trim();
            if (rawText.Length == 0)
            {
                continue;
            }

            rawText = BreakRegex().Replace(rawText, "\n");
            rawText = TagRegex().Replace(rawText, string.Empty);
            rawText = WebUtility.HtmlDecode(rawText).Trim();

            cues.Add(new SubtitleCue(start, end, rawText));
        }

        return cues.OrderBy(cue => cue.Start).ToArray();
    }

    private static bool TryParseTimestamp(string value, out TimeSpan timestamp)
    {
        timestamp = TimeSpan.Zero;
        var normalized = value.Replace(',', '.');
        var parts = normalized.Split(':');

        if (parts.Length is not (2 or 3))
        {
            return false;
        }

        var hours = 0;
        var minuteIndex = 0;
        if (parts.Length == 3)
        {
            if (!int.TryParse(parts[0], out hours))
            {
                return false;
            }
            minuteIndex = 1;
        }

        if (!int.TryParse(parts[minuteIndex], out var minutes) ||
            !double.TryParse(parts[minuteIndex + 1], System.Globalization.NumberStyles.AllowDecimalPoint,
                System.Globalization.CultureInfo.InvariantCulture, out var seconds))
        {
            return false;
        }

        timestamp = TimeSpan.FromHours(hours) + TimeSpan.FromMinutes(minutes) + TimeSpan.FromSeconds(seconds);
        return true;
    }
}
