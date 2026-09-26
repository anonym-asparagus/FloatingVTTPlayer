using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Threading;
using FloatingVttPlayer.Models;
using FloatingVttPlayer.Services;
using Forms = System.Windows.Forms;

namespace FloatingVttPlayer;

public partial class MainWindow : Window
{
    private readonly OverlayWindow _overlay;
    private readonly AudioPlayerService _audioPlayer = new();
    private readonly SettingsService _settingsService = new();
    private readonly ObservableCollection<AudioTrack> _tracks = [];
    private readonly DispatcherTimer _timer;
    private AppSettings _settings;
    private IReadOnlyList<SubtitleCue> _cues = [];
    private int _currentTrackIndex = -1;
    private bool _isSeeking;
    private bool _trackEndHandled;
    private bool _controlsInitialized;

    public MainWindow(OverlayWindow overlay)
    {
        _overlay = overlay;
        _settings = _settingsService.Load();

        InitializeComponent();
        PlaylistBox.ItemsSource = _tracks;

        _overlay.PlayPauseRequested += (_, _) => TogglePlayback();
        _overlay.HideRequested += (_, _) => Dispatcher.Invoke(() => SetOverlayVisible(false));
        _overlay.LockStateChanged += locked => Dispatcher.Invoke(() => OverlayLockedCheckBox.IsChecked = locked);
        _overlay.FontSizeChanged += size => Dispatcher.Invoke(() => FontSizeSlider.Value = size);

        RestoreSettings();
        _controlsInitialized = true;

        _timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(40) };
        _timer.Tick += Timer_OnTick;
        _timer.Start();

        if (_settings.LastFolder is { } lastFolder && Directory.Exists(lastFolder))
        {
            LoadFolder(lastFolder);
        }
    }

    public void TogglePlayback()
    {
        Dispatcher.Invoke(() =>
        {
            if (_currentTrackIndex < 0 && _tracks.Count > 0)
            {
                PlayTrack(0);
                return;
            }

            _audioPlayer.Toggle();
            UpdatePlaybackButton();
        });
    }

    public void ToggleOverlayVisibility() => Dispatcher.Invoke(() =>
        SetOverlayVisible(ShowOverlayCheckBox.IsChecked != true));

    public void ApplyInitialOverlayVisibility() => SetOverlayVisible(_settings.OverlayVisible);

    public void PlayPrevious() => Dispatcher.Invoke(() =>
    {
        if (_tracks.Count == 0) return;
        var index = _currentTrackIndex <= 0 ? _tracks.Count - 1 : _currentTrackIndex - 1;
        PlayTrack(index);
    });

    public void PlayNext() => Dispatcher.Invoke(() =>
    {
        if (_tracks.Count == 0) return;
        var index = (_currentTrackIndex + 1) % _tracks.Count;
        PlayTrack(index);
    });

    public void PrepareForExit()
    {
        SaveSettings();
        _timer.Stop();
        _audioPlayer.Dispose();
        Close();
    }

    private void RestoreSettings()
    {
        VolumeSlider.Value = Math.Clamp(_settings.Volume * 100, 0, 100);
        FontSizeSlider.Value = Math.Clamp(_settings.SubtitleFontSize, 18, 120);
        OverlayLockedCheckBox.IsChecked = _settings.OverlayLocked;
        ShowOverlayCheckBox.IsChecked = _settings.OverlayVisible;

        _audioPlayer.Volume = (float)_settings.Volume;
        _overlay.SetAppearance(_settings.SubtitleFontSize, _settings.SubtitleFontFamily,
            _settings.SubtitleTextColor, _settings.SubtitleShadowOpacity);

        _overlay.Width = Math.Max(320, _settings.OverlayWidth);
        _overlay.Height = Math.Max(100, _settings.OverlayHeight);

        if (!double.IsNaN(_settings.OverlayLeft) && !double.IsNaN(_settings.OverlayTop))
        {
            _overlay.WindowStartupLocation = WindowStartupLocation.Manual;
            _overlay.Left = _settings.OverlayLeft;
            _overlay.Top = _settings.OverlayTop;
        }
        else
        {
            var workArea = SystemParameters.WorkArea;
            _overlay.WindowStartupLocation = WindowStartupLocation.Manual;
            _overlay.Left = workArea.Left + (workArea.Width - _overlay.Width) / 2;
            _overlay.Top = workArea.Bottom - _overlay.Height - 70;
        }

        _overlay.SetLocked(_settings.OverlayLocked);
    }

    private void LoadFolder(string folderPath)
    {
        try
        {
            var audioPaths = Directory.EnumerateFiles(folderPath, "*", SearchOption.TopDirectoryOnly)
                .Where(path => Path.GetExtension(path).Equals(".wav", StringComparison.OrdinalIgnoreCase) ||
                               Path.GetExtension(path).Equals(".mp3", StringComparison.OrdinalIgnoreCase))
                .OrderBy(path => Path.GetFileName(path), LogicalStringComparer.Instance)
                .ToArray();

            var subtitles = Directory.EnumerateFiles(folderPath, "*.vtt", SearchOption.TopDirectoryOnly)
                .ToArray();
            var usedSubtitles = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

            _audioPlayer.Dispose();
            _overlay.SetSubtitle(string.Empty);
            _cues = [];
            _currentTrackIndex = -1;
            _tracks.Clear();

            foreach (var audioPath in audioPaths)
            {
                var subtitlePath = SubtitleMatcher.FindBestMatch(audioPath, subtitles, usedSubtitles);
                if (subtitlePath is not null)
                {
                    usedSubtitles.Add(subtitlePath);
                }
                _tracks.Add(new AudioTrack { AudioPath = audioPath, SubtitlePath = subtitlePath });
            }

            FolderPathText.Text = folderPath;
            _settings.LastFolder = folderPath;
            StatusText.Text = _tracks.Count == 0
                ? "No MP3 or WAV files found."
                : $"Loaded {_tracks.Count} track(s); {_tracks.Count(track => track.HasSubtitle)} matched VTT file(s).";
            UpdatePlaybackButton();
        }
        catch (Exception ex)
        {
            System.Windows.MessageBox.Show($"Could not open the folder.\n\n{ex.Message}", "Floating VTT Player",
                MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private void PlayTrack(int index)
    {
        if (index < 0 || index >= _tracks.Count)
        {
            return;
        }

        var track = _tracks[index];

        try
        {
            _audioPlayer.Open(track.AudioPath);
            _audioPlayer.Volume = (float)(VolumeSlider.Value / 100);
            _cues = track.SubtitlePath is null ? [] : WebVttParser.ParseFile(track.SubtitlePath);
            _currentTrackIndex = index;
            _trackEndHandled = false;
            PlaylistBox.SelectedIndex = index;
            PlaylistBox.ScrollIntoView(track);
            _audioPlayer.Play();

            StatusText.Text = track.HasSubtitle
                ? $"Playing {track.FileName} — {_cues.Count} subtitle cue(s)"
                : $"Playing {track.FileName} — no matching VTT";
            Title = $"{track.FileName} — Floating VTT Player";
            UpdatePlaybackButton();
        }
        catch (Exception ex)
        {
            System.Windows.MessageBox.Show($"Could not play {track.FileName}.\n\n{ex.Message}",
                "Floating VTT Player", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private void Timer_OnTick(object? sender, EventArgs e)
    {
        var current = _audioPlayer.CurrentTime;
        var total = _audioPlayer.TotalTime;

        if (!_isSeeking)
        {
            ProgressSlider.Maximum = Math.Max(1, total.TotalSeconds);
            ProgressSlider.Value = Math.Min(ProgressSlider.Maximum, current.TotalSeconds);
        }

        CurrentTimeText.Text = FormatTime(current);
        TotalTimeText.Text = FormatTime(total);

        var activeText = string.Join("\n", _cues
            .Where(cue => current >= cue.Start && current < cue.End)
            .Select(cue => cue.Text));
        _overlay.SetSubtitle(activeText);
        _overlay.SetIsPlaying(_audioPlayer.IsPlaying);

        if (!_trackEndHandled && total > TimeSpan.Zero && current >= total - TimeSpan.FromMilliseconds(120))
        {
            _trackEndHandled = true;
            PlayNext();
        }
    }

    private void SaveSettings()
    {
        _settings.SubtitleFontSize = _overlay.SubtitleFontSize;
        _settings.SubtitleFontFamily = _overlay.SubtitleFontFamilyName;
        _settings.SubtitleTextColor = _overlay.SubtitleColorHex;
        _settings.SubtitleShadowOpacity = _overlay.ShadowOpacity;
        _settings.Volume = VolumeSlider.Value / 100;
        _settings.OverlayLocked = _overlay.IsLocked;
        _settings.OverlayVisible = ShowOverlayCheckBox.IsChecked == true;
        _settings.OverlayLeft = _overlay.Left;
        _settings.OverlayTop = _overlay.PreferredTop;
        _settings.OverlayWidth = _overlay.ActualWidth > 0 ? _overlay.ActualWidth : _overlay.Width;
        _settings.OverlayHeight = _overlay.PreferredHeight;

        try
        {
            _settingsService.Save(_settings);
        }
        catch
        {
            // Closing should continue even if settings cannot be persisted.
        }
    }

    private static string FormatTime(TimeSpan value) =>
        value.TotalHours >= 1 ? value.ToString(@"h\:mm\:ss") : value.ToString(@"m\:ss");

    private void UpdatePlaybackButton()
    {
        PlayPauseButton.Content = _audioPlayer.IsPlaying ? "⏸  Pause" : "▶  Play";
    }

    private void BrowseFolder_OnClick(object sender, RoutedEventArgs e)
    {
        using var dialog = new Forms.FolderBrowserDialog
        {
            Description = "Choose a folder containing audio and matching VTT files",
            UseDescriptionForTitle = true,
            ShowNewFolderButton = false,
            InitialDirectory = Directory.Exists(_settings.LastFolder) ? _settings.LastFolder : string.Empty
        };

        if (dialog.ShowDialog() == Forms.DialogResult.OK)
        {
            LoadFolder(dialog.SelectedPath);
        }
    }

    private void Refresh_OnClick(object sender, RoutedEventArgs e)
    {
        if (_settings.LastFolder is { } lastFolder && Directory.Exists(lastFolder))
        {
            LoadFolder(lastFolder);
        }
    }

    private void PlaylistBox_OnMouseDoubleClick(object sender, MouseButtonEventArgs e)
    {
        if (PlaylistBox.SelectedIndex >= 0)
        {
            PlayTrack(PlaylistBox.SelectedIndex);
        }
    }

    private void PlayPause_OnClick(object sender, RoutedEventArgs e) => TogglePlayback();
    private void Previous_OnClick(object sender, RoutedEventArgs e) => PlayPrevious();
    private void Next_OnClick(object sender, RoutedEventArgs e) => PlayNext();

    private void ProgressSlider_OnPreviewMouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (IsInsideSliderThumb(e.OriginalSource as DependencyObject))
        {
            _isSeeking = true;
            return;
        }

        var track = ProgressSlider.Template.FindName("PART_Track", ProgressSlider) as Track;
        if (track is null || track.ActualWidth <= 0)
        {
            return;
        }

        var thumbWidth = track.Thumb?.ActualWidth ?? 0;
        var usableWidth = Math.Max(1, track.ActualWidth - thumbWidth);
        var clickX = e.GetPosition(track).X - (thumbWidth / 2);
        var ratio = Math.Clamp(clickX / usableWidth, 0, 1);
        var targetSeconds = ProgressSlider.Minimum +
                            ratio * (ProgressSlider.Maximum - ProgressSlider.Minimum);

        _isSeeking = true;
        ProgressSlider.Value = targetSeconds;
        SeekToProgressValue();
        _isSeeking = false;
        e.Handled = true;
    }

    private void ProgressSlider_OnPreviewMouseLeftButtonUp(object sender, MouseButtonEventArgs e)
    {
        if (_isSeeking)
        {
            SeekToProgressValue();
        }
        _isSeeking = false;
    }

    private void SeekToProgressValue()
    {
        var target = TimeSpan.FromSeconds(ProgressSlider.Value);
        _audioPlayer.Seek(target);
        CurrentTimeText.Text = FormatTime(target);
        _trackEndHandled = false;
    }

    private static bool IsInsideSliderThumb(DependencyObject? source)
    {
        while (source is not null)
        {
            if (source is Thumb)
            {
                return true;
            }

            source = System.Windows.Media.VisualTreeHelper.GetParent(source);
        }

        return false;
    }

    private void VolumeSlider_OnValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (VolumeValueText is null) return;
        VolumeValueText.Text = $"{VolumeSlider.Value:0}%";
        _audioPlayer.Volume = (float)(VolumeSlider.Value / 100);
    }

    private void FontSizeSlider_OnValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (FontSizeValueText is null) return;
        FontSizeValueText.Text = $"{FontSizeSlider.Value:0} px";
        _overlay.SetFontSize(FontSizeSlider.Value);
    }

    private void OverlayLocked_OnChanged(object sender, RoutedEventArgs e)
    {
        if (!_controlsInitialized && !IsLoaded) return;
        _overlay.SetLocked(OverlayLockedCheckBox.IsChecked == true);
    }

    private void ShowOverlay_OnChanged(object sender, RoutedEventArgs e)
    {
        if (!_controlsInitialized && !IsLoaded) return;
        SetOverlayVisible(ShowOverlayCheckBox.IsChecked == true);
    }

    private void SetOverlayVisible(bool visible)
    {
        ShowOverlayCheckBox.IsChecked = visible;
        if (visible)
        {
            _overlay.Show();
            _overlay.Topmost = true;
        }
        else
        {
            _overlay.Hide();
        }
    }

    private void HideToTray_OnClick(object sender, RoutedEventArgs e) => Hide();

    protected override void OnClosing(CancelEventArgs e)
    {
        if (((App)System.Windows.Application.Current).IsExiting)
        {
            base.OnClosing(e);
            return;
        }

        e.Cancel = true;
        Hide();
        StatusText.Text = "Player controls hidden. Double-click the tray icon to restore them.";
    }

    private sealed class LogicalStringComparer : IComparer<string>
    {
        public static LogicalStringComparer Instance { get; } = new();

        public int Compare(string? x, string? y) => StrCmpLogicalW(x ?? string.Empty, y ?? string.Empty);

        [DllImport("shlwapi.dll", CharSet = CharSet.Unicode)]
        private static extern int StrCmpLogicalW(string left, string right);
    }
}
