using System.Collections.Concurrent;
using System.Diagnostics;
using System.Runtime.InteropServices;
using Sidey.Core.Domain;
using Sidey.Core.Overlay;
using Windows.Media.Devices;

namespace Sidey.Platform.Windows.Audio;

/// <summary>Keeps a shared XAudio2 output graph ready; PCM submission runs outside UI/render threads.</summary>
public sealed class WindowsImpactAudio : IDisposable
{
    private sealed class Voice(nint handle)
    {
        public nint Handle { get; } = handle;
        public bool Active;
        public Guid Scope;
    }

    private sealed class ScopeLease { public bool Stopped; }
    private readonly Action<string, Exception> _diagnostic;
    private readonly BlockingCollection<Action> _work = [];
    private readonly Dictionary<string, (nint Data, int Length)> _samples = [];
    private readonly List<Voice> _voices = [];
    private XAudio2Output? _output;
    private readonly ImpactSoundAdmission _admission = new();
    private readonly Dictionary<Guid, ScopeLease> _scopeLeases = [];
    private readonly Lock _gate = new();
    private long _generation;
    private int _pendingPlays;
    private bool _enabled = true;
    private int _volume = 100;
    private bool _volumeUpdateQueued;
    private bool _disposed;
    private volatile bool _ready;
    private Guid? _lastStartedScope;
    private static double Now => (double)Stopwatch.GetTimestamp() / Stopwatch.Frequency;

    public WindowsImpactAudio(Action<string, Exception> diagnostic)
    {
        _diagnostic = diagnostic;
        var thread = new Thread(Run) { IsBackground = true, Name = "SIDEY impact audio" };
        thread.SetApartmentState(ApartmentState.MTA);
        MediaDevice.DefaultAudioRenderDeviceChanged += OnDeviceChanged;
        thread.Start();
    }

    private void Run()
    {
        try
        {
            foreach (string id in ImpactSoundCatalog.Ids)
            {
                try
                {
                    string path = Path.Combine(SideyDeploymentPaths.DeploymentRoot(), "Assets", "Impacts", id, id + ".wav");
                    byte[] pcm = ImpactWaveData.Read(File.ReadAllBytes(path));
                    nint data = Marshal.AllocHGlobal(pcm.Length);
                    Marshal.Copy(pcm, 0, data, pcm.Length);
                    _samples.Add(id, (data, pcm.Length));
                }
                catch (Exception exception) { Report("impact-prepare-" + id, exception); }
            }
            ReopenVoices();
            foreach (Action action in _work.GetConsumingEnumerable())
            {
                lock (_gate)
                    if (_disposed)
                        break;
                try
                { action(); }
                catch (Exception exception) { Report("impact-audio", exception); }
            }
        }
        catch (Exception exception) { Report("impact-initialize", exception); }
        finally
        {
            lock (_gate)
            {
                _disposed = true;
                _work.CompleteAdding();
            }
            MediaDevice.DefaultAudioRenderDeviceChanged -= OnDeviceChanged;
            _ready = false;
            CloseVoices();
            foreach ((nint Data, int Length) sample in _samples.Values)
                Marshal.FreeHGlobal(sample.Data);
            _work.Dispose();
        }
    }

    private void ReopenVoices()
    {
        _ready = false;
        CloseVoices();
        try
        {
            _output = new XAudio2Output();
            _output.SetVolume(Volatile.Read(ref _volume));
            for (int i = 0; i < 4; i++)
                _voices.Add(new Voice(_output.CreateVoice()));
            UpdateEngineRunning();
            _admission.Reset();
            _ready = _samples.Count == ImpactSoundCatalog.Ids.Count;
        }
        catch (Exception exception)
        {
            Report("impact-output-prepare", exception);
            CloseVoices();
        }
    }

    public void SetEnabled(bool enabled)
    {
        lock (_gate)
        {
            if (_disposed)
                return;
            _enabled = enabled;
            _work.Add(UpdateEngineRunning);
        }
        if (!enabled)
            StopAll();
    }

    public void Play(string id, Guid scope, long requestedAt)
    {
        lock (_gate)
        {
            if (_disposed || !_enabled || _volume == 0 || !_ready || _pendingPlays >= 64 || !ImpactSoundCatalog.Ids.Contains(id))
                return;
            long generation = _generation;
            if (!_scopeLeases.TryGetValue(scope, out ScopeLease? lease))
                _scopeLeases[scope] = lease = new ScopeLease();
            _pendingPlays++;
            _work.Add(() =>
            {
                lock (_gate)
                {
                    _pendingPlays--;
                    if (_disposed || !_enabled || _volume == 0 || _generation != generation || lease.Stopped)
                        return;
                }
                RefreshCompletedVoices();
                if (!_ready || WindowsActivityMonitor.IsScreenLocked() || !_admission.Accept(Now,
                    (double)requestedAt / Stopwatch.Frequency, _voices.Count(v => v.Active), true))
                    return;
                Voice available = _voices.First(v => !v.Active);
                if (!_samples.TryGetValue(id, out (nint Data, int Length) sample))
                    return;
                available.Scope = scope;
                _output!.SetRunning(true);
                XAudio2Output.Play(available.Handle, sample.Data, sample.Length);
                available.Active = true;
                _lastStartedScope = scope;
            });
        }
    }

    public void SetVolume(int volume)
    {
        lock (_gate)
        {
            if (_disposed)
                return;
            _volume = Math.Clamp(volume, 0, 100);
            if (_volume == 0)
            {
                _generation++;
                _scopeLeases.Clear();
            }
            if (_volumeUpdateQueued)
                return;
            _volumeUpdateQueued = true;
            _work.Add(() =>
            {
                int latest;
                lock (_gate)
                { latest = _volume; _volumeUpdateQueued = false; }
                _output?.SetVolume(latest);
                if (latest == 0)
                    foreach (Voice voice in _voices)
                        StopVoice(voice);
                UpdateEngineRunning();
            });
        }
    }

    private void UpdateEngineRunning()
    {
        bool enabled;
        lock (_gate)
            enabled = _enabled && _volume > 0;
        _output?.SetRunning(enabled && !WindowsActivityMonitor.IsScreenLocked());
    }

    private void RefreshCompletedVoices()
    {
        foreach (Voice voice in _voices)
            if (voice.Active && XAudio2Output.QueuedBuffers(voice.Handle) == 0)
            {
                voice.Active = false;
            }
    }

    public void StopScope(Guid scope)
    {
        lock (_gate)
        {
            if (_disposed)
                return;
            if (_scopeLeases.Remove(scope, out ScopeLease? lease))
                lease.Stopped = true;
            _work.Add(() =>
            {
                foreach (Voice? voice in _voices.Where(v => v.Scope == scope))
                    StopVoice(voice);
                if (_lastStartedScope == scope)
                { _admission.Reset(); _lastStartedScope = null; }
            });
        }
    }

    public void StopAll()
    {
        lock (_gate)
        {
            if (_disposed)
                return;
            _generation++;
            _scopeLeases.Clear();
            _work.Add(() => { foreach (Voice voice in _voices) StopVoice(voice); _admission.Reset(); UpdateEngineRunning(); });
        }
    }

    private static void StopVoice(Voice voice)
    {
        if (!voice.Active)
            return;
        XAudio2Output.Stop(voice.Handle);
        voice.Active = false;
    }

    private void CloseVoices()
    {
        // DestroyVoice synchronizes with the native engine before PCM memory is released.
        foreach (Voice voice in _voices)
            XAudio2Output.DestroyVoice(voice.Handle);
        _voices.Clear();
        _output?.Dispose();
        _output = null;
    }

    private void OnDeviceChanged(object sender, DefaultAudioRenderDeviceChangedEventArgs args)
    {
        lock (_gate)
        {
            if (_disposed)
                return;
            _ready = false;
            _generation++;
            _scopeLeases.Clear();
            _work.Add(ReopenVoices);
        }
    }

    private void Report(string stage, Exception exception)
    {
        try
        { _diagnostic(stage, exception); }
        catch { /* Diagnostics must not terminate the audio worker. */ }
    }

    public void Dispose()
    {
        lock (_gate)
        {
            if (_disposed)
                return;
            _disposed = true;
            _ready = false;
            _generation++;
            _work.CompleteAdding();
        }
        MediaDevice.DefaultAudioRenderDeviceChanged -= OnDeviceChanged;
    }

}
