namespace FloatingVttPlayer.Models;

public sealed record SubtitleCue(TimeSpan Start, TimeSpan End, string Text);
