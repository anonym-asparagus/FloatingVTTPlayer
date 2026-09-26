namespace FloatingVttPlayer.Models;

public sealed class AudioTrack
{
    public required string AudioPath { get; init; }
    public string? SubtitlePath { get; init; }

    public string FileName => Path.GetFileName(AudioPath);
    public bool HasSubtitle => SubtitlePath is not null;
    public string DisplayName => HasSubtitle ? $"{FileName}    ✓ VTT" : $"{FileName}    — no VTT";
}
