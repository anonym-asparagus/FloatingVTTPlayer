using System.Drawing;
using System.Windows;
using Forms = System.Windows.Forms;

namespace FloatingVttPlayer;

public partial class App : System.Windows.Application
{
    private Forms.NotifyIcon? _trayIcon;
    private Icon? _appIcon;
    private bool _isExiting;

    public MainWindow MainPlayerWindow { get; private set; } = null!;
    public OverlayWindow SubtitleOverlay { get; private set; } = null!;
    public bool IsExiting => _isExiting;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        SubtitleOverlay = new OverlayWindow();
        MainPlayerWindow = new MainWindow(SubtitleOverlay);

        CreateTrayIcon();
        MainPlayerWindow.Show();
        MainPlayerWindow.ApplyInitialOverlayVisibility();

        if (e.Args.Contains("--smoke-test", StringComparer.OrdinalIgnoreCase))
        {
            _ = Task.Delay(1200).ContinueWith(_ => Dispatcher.Invoke(ExitApplication));
        }
    }

    private void CreateTrayIcon()
    {
        if (Environment.ProcessPath is { } executablePath)
        {
            _appIcon = Icon.ExtractAssociatedIcon(executablePath);
        }

        var menu = new Forms.ContextMenuStrip();
        menu.Items.Add("Open player", null, (_, _) => ShowMainWindow());
        menu.Items.Add("Play / Pause", null, (_, _) => MainPlayerWindow.TogglePlayback());
        menu.Items.Add("Previous", null, (_, _) => MainPlayerWindow.PlayPrevious());
        menu.Items.Add("Next", null, (_, _) => MainPlayerWindow.PlayNext());
        menu.Items.Add("Show / hide subtitles", null, (_, _) => MainPlayerWindow.ToggleOverlayVisibility());
        menu.Items.Add(new Forms.ToolStripSeparator());
        menu.Items.Add("Exit", null, (_, _) => ExitApplication());

        _trayIcon = new Forms.NotifyIcon
        {
            Icon = _appIcon ?? SystemIcons.Application,
            Text = "Floating VTT Player",
            Visible = true,
            ContextMenuStrip = menu
        };
        _trayIcon.DoubleClick += (_, _) => ShowMainWindow();
    }

    public void ShowMainWindow()
    {
        Dispatcher.Invoke(() =>
        {
            MainPlayerWindow.Show();
            MainPlayerWindow.WindowState = WindowState.Normal;
            MainPlayerWindow.Activate();
        });
    }

    public void ExitApplication()
    {
        if (_isExiting)
        {
            return;
        }

        _isExiting = true;
        MainPlayerWindow.PrepareForExit();
        SubtitleOverlay.PrepareForExit();

        if (_trayIcon is not null)
        {
            _trayIcon.Visible = false;
            _trayIcon.Dispose();
        }

        _appIcon?.Dispose();

        Shutdown();
    }
}
