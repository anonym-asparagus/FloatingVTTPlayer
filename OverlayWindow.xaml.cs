using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Threading;
using System.Runtime.InteropServices;
using Media = System.Windows.Media;
using Forms = System.Windows.Forms;

namespace FloatingVttPlayer;

public partial class OverlayWindow : Window
{
    private const int WmNcLButtonDown = 0x00A1;
    private const int HtBottomRight = 17;

    private bool _isLocked = true;
    private bool _allowClose;
    private double _preferredHeight = 190;
    private double? _automaticHeight;

    public event EventHandler? PlayPauseRequested;
    public event EventHandler? HideRequested;
    public event Action<bool>? LockStateChanged;
    public event Action<double>? FontSizeChanged;

    public bool IsLocked => _isLocked;
    public double SubtitleFontSize => SubtitleText.FontSize;
    public string SubtitleFontFamilyName => SubtitleText.FontFamily.Source;
    public string SubtitleColorHex => ((Media.SolidColorBrush)SubtitleText.Foreground).Color.ToString();
    public double ShadowOpacity => SubtitleShadow.Opacity;
    public double PreferredHeight => _preferredHeight;
    public double PreferredTop => Top + Height - _preferredHeight;

    public OverlayWindow()
    {
        InitializeComponent();

        FontFamilyBox.ItemsSource = Media.Fonts.SystemFontFamilies
            .Select(font => font.Source)
            .OrderBy(name => name, StringComparer.CurrentCultureIgnoreCase)
            .ToArray();

        SizeChanged += OverlayWindow_OnSizeChanged;

        Closing += (_, e) =>
        {
            if (!_allowClose)
            {
                e.Cancel = true;
                HideRequested?.Invoke(this, EventArgs.Empty);
            }
        };
    }

    public void SetSubtitle(string text)
    {
        if (SubtitleText.Text == text)
        {
            return;
        }

        SubtitleText.Text = text;
        EnsureSubtitleFits();
    }

    public void SetIsPlaying(bool isPlaying)
    {
        OverlayPlayPauseButton.Content = isPlaying ? "⏸" : "▶";
        OverlayPlayPauseButton.ToolTip = isPlaying ? "Pause" : "Play";
    }

    public void SetAppearance(double size, string fontFamily, string colorHex, double shadowOpacity)
    {
        SetFontSize(size);
        var installedFont = FontFamilyBox.Items.Cast<string>()
            .FirstOrDefault(name => name.Equals(fontFamily, StringComparison.OrdinalIgnoreCase));
        FontFamilyBox.SelectedItem = installedFont ?? "Segoe UI";
        SubtitleText.FontFamily = new Media.FontFamily(installedFont ?? "Segoe UI");

        try
        {
            var color = (Media.Color)Media.ColorConverter.ConvertFromString(colorHex);
            SubtitleText.Foreground = new Media.SolidColorBrush(color);
            TextColorButton.Foreground = new Media.SolidColorBrush(color);
        }
        catch
        {
            SubtitleText.Foreground = Media.Brushes.White;
            TextColorButton.Foreground = Media.Brushes.White;
        }

        HexColorTextBox.Text = ToRgbHex(((Media.SolidColorBrush)SubtitleText.Foreground).Color);
        ShadowSlider.Value = Math.Clamp(shadowOpacity, 0, 1) * 100;
        SubtitleShadow.Opacity = ShadowSlider.Value / 100;
        ShadowValueText.Text = $"{ShadowSlider.Value:0}%";
    }

    public void SetFontSize(double size)
    {
        var value = Math.Clamp(size, 18, 120);
        SubtitleText.FontSize = value;
        ToolbarFontSizeText.Text = $"{value:0}";
        EnsureSubtitleFits();
        FontSizeChanged?.Invoke(value);
    }

    public void SetLocked(bool locked)
    {
        var changed = _isLocked != locked;
        _isLocked = locked;
        if (locked)
        {
            ColorPopup.IsOpen = false;
            ShadowPopup.IsOpen = false;
        }
        ResizeMode = locked ? ResizeMode.NoResize : ResizeMode.CanResize;
        AppearanceControls.Visibility = locked ? Visibility.Collapsed : Visibility.Visible;
        LockButton.Content = locked ? "🔒" : "🔓";
        LockButton.ToolTip = locked ? "Unlock position and appearance" : "Lock subtitle position";
        UpdateHoverChrome(IsMouseOver);
        EnsureSubtitleFits();
        if (changed)
        {
            LockStateChanged?.Invoke(locked);
        }
    }

    public void PrepareForExit()
    {
        _allowClose = true;
        Close();
    }

    private void OverlayWindow_OnSizeChanged(object sender, SizeChangedEventArgs e)
    {
        if (e.HeightChanged)
        {
            if (_automaticHeight is double automaticHeight &&
                Math.Abs(e.NewSize.Height - automaticHeight) < 1)
            {
                _automaticHeight = null;
            }
            else
            {
                _preferredHeight = e.NewSize.Height;
                _automaticHeight = null;
            }
        }

        Dispatcher.BeginInvoke(EnsureSubtitleFits, DispatcherPriority.Loaded);
    }

    private void EnsureSubtitleFits()
    {
        var width = ActualWidth > 0 ? ActualWidth : Width;
        if (!double.IsFinite(width) || width <= 0)
        {
            return;
        }

        var border = OverlayBorder.BorderThickness;
        var padding = OverlayBorder.Padding;
        var textWidth = Math.Max(1, width - border.Left - border.Right - padding.Left - padding.Right);

        HoverToolbar.Measure(new System.Windows.Size(double.PositiveInfinity, double.PositiveInfinity));
        SubtitleText.Measure(new System.Windows.Size(textWidth, double.PositiveInfinity));

        var requiredHeight = border.Top + border.Bottom + padding.Top + padding.Bottom +
                             HoverToolbar.DesiredSize.Height + SubtitleText.DesiredSize.Height + 8;
        var targetHeight = Math.Max(_preferredHeight, Math.Ceiling(requiredHeight));
        if (Math.Abs(Height - targetHeight) < 1)
        {
            return;
        }

        var bottom = Top + Height;
        _automaticHeight = targetHeight;
        Height = targetHeight;
        if (double.IsFinite(bottom))
        {
            Top = bottom - targetHeight;
        }
    }

    private void Window_OnMouseEnter(object sender, System.Windows.Input.MouseEventArgs e)
    {
        UpdateHoverChrome(true);
    }

    private void Window_OnMouseLeave(object sender, System.Windows.Input.MouseEventArgs e)
    {
        if (ColorPopup.IsOpen || ShadowPopup.IsOpen || FontFamilyBox.IsDropDownOpen)
        {
            return;
        }

        UpdateHoverChrome(false);
    }

    private void UpdateHoverChrome(bool hovered)
    {
        HoverToolbar.Visibility = hovered ? Visibility.Visible : Visibility.Hidden;
        CloseOverlayButton.Visibility = hovered ? Visibility.Visible : Visibility.Collapsed;

        var showUnlockedChrome = hovered && !_isLocked;
        OverlayBorder.Background = showUnlockedChrome
            ? new Media.SolidColorBrush(Media.Color.FromArgb(70, 17, 24, 39))
            : new Media.SolidColorBrush(Media.Color.FromArgb(1, 0, 0, 0));
        OverlayBorder.BorderBrush = showUnlockedChrome
            ? new Media.SolidColorBrush(Media.Color.FromRgb(96, 165, 250))
            : Media.Brushes.Transparent;
        OverlayResizeGrip.Visibility = showUnlockedChrome ? Visibility.Visible : Visibility.Collapsed;
    }

    private void AppearancePopup_OnClosed(object? sender, EventArgs e)
    {
        if (!IsMouseOver && !ColorPopup.IsOpen && !ShadowPopup.IsOpen)
        {
            UpdateHoverChrome(false);
        }
    }

    private void FontFamilyBox_OnDropDownClosed(object sender, EventArgs e)
    {
        if (!IsMouseOver && !ColorPopup.IsOpen && !ShadowPopup.IsOpen)
        {
            UpdateHoverChrome(false);
        }
    }

    private void Window_OnPreviewMouseWheel(object sender, MouseWheelEventArgs e)
    {
        if (_isLocked)
        {
            return;
        }

        SetFontSize(SubtitleText.FontSize + (e.Delta > 0 ? 2 : -2));
        e.Handled = true;
    }

    private void OverlayBorder_OnMouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (_isLocked || e.LeftButton != MouseButtonState.Pressed ||
            IsInsideToolbar(e.OriginalSource as DependencyObject))
        {
            return;
        }

        DragMove();
    }

    private void OverlayResizeGrip_OnPreviewMouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (_isLocked || e.ChangedButton != MouseButton.Left)
        {
            return;
        }

        e.Handled = true;
        ReleaseCapture();
        var windowHandle = new WindowInteropHelper(this).Handle;
        if (windowHandle != IntPtr.Zero)
        {
            SendMessage(windowHandle, WmNcLButtonDown, HtBottomRight, 0);
        }
    }

    private bool IsInsideToolbar(DependencyObject? source)
    {
        while (source is not null)
        {
            if (ReferenceEquals(source, HoverToolbar) || ReferenceEquals(source, CloseOverlayButton))
            {
                return true;
            }
            source = Media.VisualTreeHelper.GetParent(source);
        }
        return false;
    }

    [DllImport("user32.dll")]
    private static extern bool ReleaseCapture();

    [DllImport("user32.dll")]
    private static extern IntPtr SendMessage(IntPtr windowHandle, int message, int wParam, int lParam);

    private void OverlayPlayPauseButton_OnClick(object sender, RoutedEventArgs e) =>
        PlayPauseRequested?.Invoke(this, EventArgs.Empty);

    private void LockButton_OnClick(object sender, RoutedEventArgs e) => SetLocked(!_isLocked);

    private void CloseOverlayButton_OnClick(object sender, RoutedEventArgs e) =>
        HideRequested?.Invoke(this, EventArgs.Empty);

    private void DecreaseFontSize_OnClick(object sender, RoutedEventArgs e) =>
        SetFontSize(SubtitleText.FontSize - 2);

    private void IncreaseFontSize_OnClick(object sender, RoutedEventArgs e) =>
        SetFontSize(SubtitleText.FontSize + 2);

    private void FontFamilyBox_OnSelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (FontFamilyBox.SelectedItem is string fontName)
        {
            SubtitleText.FontFamily = new Media.FontFamily(fontName);
        }
    }

    private void TextColorButton_OnClick(object sender, RoutedEventArgs e)
    {
        ShadowPopup.IsOpen = false;
        ColorValidationText.Visibility = Visibility.Collapsed;
        ColorPopup.IsOpen = !ColorPopup.IsOpen;
    }

    private void ShadowButton_OnClick(object sender, RoutedEventArgs e)
    {
        ColorPopup.IsOpen = false;
        ShadowPopup.IsOpen = !ShadowPopup.IsOpen;
    }

    private void PaletteColorButton_OnClick(object sender, RoutedEventArgs e)
    {
        if (sender is System.Windows.Controls.Button { Tag: string hex })
        {
            ApplyTextColor(hex);
            ColorPopup.IsOpen = false;
        }
    }

    private void ApplyHexColor_OnClick(object sender, RoutedEventArgs e) => ApplyHexColor();

    private void HexColorTextBox_OnKeyDown(object sender, System.Windows.Input.KeyEventArgs e)
    {
        if (e.Key == Key.Enter)
        {
            ApplyHexColor();
            e.Handled = true;
        }
    }

    private void ApplyHexColor()
    {
        var value = HexColorTextBox.Text.Trim();
        if (!value.StartsWith('#'))
        {
            value = $"#{value}";
        }

        if (value.Length is not (7 or 9))
        {
            ShowColorValidation("Enter #RRGGBB or #AARRGGBB.");
            return;
        }

        if (!ApplyTextColor(value))
        {
            ShowColorValidation("That hex color is not valid.");
            return;
        }

        ColorPopup.IsOpen = false;
    }

    private bool ApplyTextColor(string value)
    {
        try
        {
            var color = (Media.Color)Media.ColorConverter.ConvertFromString(value);
            var brush = new Media.SolidColorBrush(color);
            SubtitleText.Foreground = brush;
            TextColorButton.Foreground = brush;
            HexColorTextBox.Text = color.A == byte.MaxValue ? ToRgbHex(color) : color.ToString();
            ColorValidationText.Visibility = Visibility.Collapsed;
            return true;
        }
        catch
        {
            return false;
        }
    }

    private void ShowColorValidation(string message)
    {
        ColorValidationText.Text = message;
        ColorValidationText.Visibility = Visibility.Visible;
    }

    private static string ToRgbHex(Media.Color color) => $"#{color.R:X2}{color.G:X2}{color.B:X2}";

    private void MoreColors_OnClick(object sender, RoutedEventArgs e)
    {
        var current = ((Media.SolidColorBrush)SubtitleText.Foreground).Color;
        using var dialog = new Forms.ColorDialog
        {
            FullOpen = true,
            Color = System.Drawing.Color.FromArgb(current.A, current.R, current.G, current.B)
        };

        if (dialog.ShowDialog() != Forms.DialogResult.OK)
        {
            return;
        }

        var color = Media.Color.FromArgb(dialog.Color.A, dialog.Color.R, dialog.Color.G, dialog.Color.B);
        ApplyTextColor(color.ToString());
        ColorPopup.IsOpen = false;
    }

    private void ShadowSlider_OnValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (SubtitleShadow is not null)
        {
            SubtitleShadow.Opacity = ShadowSlider.Value / 100;
        }
        if (ShadowValueText is not null)
        {
            ShadowValueText.Text = $"{ShadowSlider.Value:0}%";
        }
    }
}
