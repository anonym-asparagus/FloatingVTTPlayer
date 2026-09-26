using System.Text.Json;
using FloatingVttPlayer.Models;

namespace FloatingVttPlayer.Services;

public sealed class SettingsService
{
    private readonly string _settingsPath;
    private readonly JsonSerializerOptions _jsonOptions = new() { WriteIndented = true };

    public SettingsService()
    {
        var directory = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "FloatingVttPlayer");
        Directory.CreateDirectory(directory);
        _settingsPath = Path.Combine(directory, "settings.json");
    }

    public AppSettings Load()
    {
        try
        {
            if (File.Exists(_settingsPath))
            {
                return JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(_settingsPath), _jsonOptions)
                       ?? new AppSettings();
            }
        }
        catch
        {
            // A malformed settings file should never prevent the player from opening.
        }

        return new AppSettings();
    }

    public void Save(AppSettings settings)
    {
        File.WriteAllText(_settingsPath, JsonSerializer.Serialize(settings, _jsonOptions));
    }
}
