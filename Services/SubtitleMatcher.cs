using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

namespace FloatingVttPlayer.Services;

public static partial class SubtitleMatcher
{
    private static readonly HashSet<string> KnownExtensions = new(StringComparer.OrdinalIgnoreCase)
    {
        ".vtt", ".wav", ".wave", ".mp3"
    };

    [GeneratedRegex(@"\d+")]
    private static partial Regex NumberRegex();

    public static string? FindBestMatch(
        string audioPath,
        IEnumerable<string> subtitlePaths,
        ISet<string>? excludedPaths = null)
    {
        var candidates = subtitlePaths
            .Where(path => excludedPaths is null || !excludedPaths.Contains(path))
            .Select(path => new { Path = path, Score = Score(audioPath, path) })
            .Where(candidate => candidate.Score >= 0)
            .OrderByDescending(candidate => candidate.Score)
            .ThenBy(candidate => Path.GetFileName(candidate.Path), StringComparer.OrdinalIgnoreCase)
            .ToArray();

        return candidates.FirstOrDefault()?.Path;
    }

    internal static double Score(string audioPath, string subtitlePath)
    {
        var audioFileName = Path.GetFileName(audioPath);
        var subtitleFileName = Path.GetFileName(subtitlePath);
        var subtitleWithoutVtt = Path.GetFileNameWithoutExtension(subtitleFileName);

        // Handles "track.wav" + "track.wav.vtt".
        if (subtitleWithoutVtt.Equals(audioFileName, StringComparison.OrdinalIgnoreCase))
        {
            return 100_000;
        }

        var audioCore = StripKnownExtensions(audioFileName);
        var subtitleCore = StripKnownExtensions(subtitleFileName);

        // Handles "track.wav" + "track.vtt".
        if (audioCore.Equals(subtitleCore, StringComparison.OrdinalIgnoreCase))
        {
            return 98_000;
        }

        var normalizedAudio = Normalize(audioCore);
        var normalizedSubtitle = Normalize(subtitleCore);
        if (normalizedAudio.Length == 0 || normalizedSubtitle.Length == 0)
        {
            return -1;
        }

        // Treats spaces plus Chinese/Western punctuation as insignificant.
        if (normalizedAudio.Equals(normalizedSubtitle, StringComparison.Ordinal))
        {
            return 96_000;
        }

        var audioNumbers = ExtractNumbers(audioCore);
        var subtitleNumbers = ExtractNumbers(subtitleCore);
        var similarity = Similarity(normalizedAudio, normalizedSubtitle);

        // Numeric track identifiers have priority over fuzzy title similarity.
        if (audioNumbers.Count > 0 && subtitleNumbers.Count > 0)
        {
            if (audioNumbers.SequenceEqual(subtitleNumbers))
            {
                return 90_000 + similarity * 5_000;
            }

            if (audioNumbers[0] == subtitleNumbers[0])
            {
                return 85_000 + similarity * 5_000;
            }

            // Different leading track numbers should never be paired merely because
            // the surrounding title text happens to look similar.
            return -1;
        }

        // Fallback for unnumbered files with small spelling/punctuation differences.
        return similarity >= 0.78 ? 60_000 + similarity * 10_000 : -1;
    }

    private static string StripKnownExtensions(string fileName)
    {
        var result = fileName;
        while (true)
        {
            var extension = Path.GetExtension(result);
            if (extension.Length == 0 || !KnownExtensions.Contains(extension))
            {
                return result;
            }

            result = Path.GetFileNameWithoutExtension(result);
        }
    }

    private static string Normalize(string value)
    {
        var normalized = value.Normalize(NormalizationForm.FormKC).ToLowerInvariant();
        var builder = new StringBuilder(normalized.Length);

        foreach (var character in normalized)
        {
            if (char.IsLetterOrDigit(character))
            {
                builder.Append(character);
            }
        }

        return builder.ToString();
    }

    private static IReadOnlyList<string> ExtractNumbers(string value) =>
        NumberRegex().Matches(value.Normalize(NormalizationForm.FormKC))
            .Select(match => CanonicalizeNumber(match.Value))
            .ToArray();

    private static string CanonicalizeNumber(string value)
    {
        var asciiDigits = new StringBuilder(value.Length);
        foreach (var character in value)
        {
            var numericValue = CharUnicodeInfo.GetDecimalDigitValue(character);
            if (numericValue >= 0)
            {
                asciiDigits.Append((char)('0' + numericValue));
            }
        }

        var canonical = asciiDigits.ToString().TrimStart('0');
        return canonical.Length == 0 ? "0" : canonical;
    }

    private static double Similarity(string left, string right)
    {
        if (left == right)
        {
            return 1;
        }

        var maximumLength = Math.Max(left.Length, right.Length);
        if (maximumLength == 0)
        {
            return 1;
        }

        return 1.0 - (double)LevenshteinDistance(left, right) / maximumLength;
    }

    private static int LevenshteinDistance(string left, string right)
    {
        if (left.Length > right.Length)
        {
            (left, right) = (right, left);
        }

        var previous = new int[left.Length + 1];
        var current = new int[left.Length + 1];
        for (var i = 0; i <= left.Length; i++)
        {
            previous[i] = i;
        }

        for (var row = 1; row <= right.Length; row++)
        {
            current[0] = row;
            for (var column = 1; column <= left.Length; column++)
            {
                var substitutionCost = left[column - 1] == right[row - 1] ? 0 : 1;
                current[column] = Math.Min(
                    Math.Min(current[column - 1] + 1, previous[column] + 1),
                    previous[column - 1] + substitutionCost);
            }

            (previous, current) = (current, previous);
        }

        return previous[left.Length];
    }
}
