using NAudio.Wave;

namespace FloatingVttPlayer.Services;

public sealed class AudioPlayerService : IDisposable
{
    private WaveOutEvent? _output;
    private AudioFileReader? _reader;
    private float _volume = 0.8f;

    public string? CurrentPath { get; private set; }
    public bool IsPlaying => _output?.PlaybackState == PlaybackState.Playing;
    public bool IsPaused => _output?.PlaybackState == PlaybackState.Paused;
    public TimeSpan CurrentTime => _reader?.CurrentTime ?? TimeSpan.Zero;
    public TimeSpan TotalTime => _reader?.TotalTime ?? TimeSpan.Zero;

    public float Volume
    {
        get => _volume;
        set
        {
            _volume = Math.Clamp(value, 0f, 1f);
            if (_reader is not null)
            {
                _reader.Volume = _volume;
            }
        }
    }

    public void Open(string path)
    {
        DisposePlayback();

        _reader = new AudioFileReader(path) { Volume = _volume };
        _output = new WaveOutEvent { DesiredLatency = 100 };
        _output.Init(_reader);
        CurrentPath = path;
    }

    public void Play() => _output?.Play();
    public void Pause() => _output?.Pause();

    public void Toggle()
    {
        if (IsPlaying)
        {
            Pause();
        }
        else
        {
            Play();
        }
    }

    public void Seek(TimeSpan position)
    {
        if (_reader is null)
        {
            return;
        }

        _reader.CurrentTime = position < TimeSpan.Zero
            ? TimeSpan.Zero
            : position > _reader.TotalTime ? _reader.TotalTime : position;
    }

    public void Dispose()
    {
        DisposePlayback();
        GC.SuppressFinalize(this);
    }

    private void DisposePlayback()
    {
        _output?.Stop();
        _output?.Dispose();
        _reader?.Dispose();
        _output = null;
        _reader = null;
        CurrentPath = null;
    }
}
