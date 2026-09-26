namespace FloatingVttPlayer.Models;

public sealed class AppSettings
{
    public string? LastFolder { get; set; }
    public double SubtitleFontSize { get; set; } = 52;
    public string SubtitleFontFamily { get; set; } = "Segoe UI";
    public string SubtitleTextColor { get; set; } = "#FFFFFFFF";
    public double SubtitleShadowOpacity { get; set; } = 1;
    public double Volume { get; set; } = 0.8;
    public bool OverlayLocked { get; set; } = false;
    public bool OverlayVisible { get; set; } = true;
    public double OverlayLeft { get; set; } = double.NaN;
    public double OverlayTop { get; set; } = double.NaN;
    public double OverlayWidth { get; set; } = 1000;
    public double OverlayHeight { get; set; } = 190;
}
