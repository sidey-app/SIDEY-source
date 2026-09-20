using System.Runtime.InteropServices;

namespace Sidey.Platform.Windows.Audio;

/// <summary>Windows 10+ XAudio2.9 ABI. Owned and called exclusively by the audio worker.</summary>
internal sealed unsafe class XAudio2Output : IDisposable
{
    private nint _engine;
    private nint _master;
    private bool _running;
    private bool _comInitialized;

    public XAudio2Output()
    {
        try
        {
            Marshal.ThrowExceptionForHR(CoInitializeEx(0, 0));
            _comInitialized = true;
            Marshal.ThrowExceptionForHR(XAudio2Create(out _engine, 0, 0));
            nint master;
            // Default virtual endpoint follows Windows routing; GameEffects category, 48 kHz.
            Marshal.ThrowExceptionForHR(((delegate* unmanaged[Stdcall]<nint, nint*, uint, uint, uint, nint, nint, int, int>)Table(_engine)[7])(
                _engine, &master, 0, 48000, 0, 0, 0, 6));
            _master = master;
            _running = true; // XAudio2Create starts the engine.
        }
        catch { Dispose(); throw; }
    }

    public nint CreateVoice()
    {
        var format = new WaveFormat
        {
            FormatTag = 1,
            Channels = 1,
            SamplesPerSecond = 48000,
            AverageBytesPerSecond = 96000,
            BlockAlign = 2,
            BitsPerSample = 16
        };
        nint voice;
        Marshal.ThrowExceptionForHR(((delegate* unmanaged[Stdcall]<nint, nint*, WaveFormat*, uint, float, nint, nint, nint, int>)Table(_engine)[5])(
            _engine, &voice, &format, 0, 1, 0, 0, 0));
        return voice;
    }

    public void SetRunning(bool running)
    {
        if (_running == running)
            return;
        if (running)
            Marshal.ThrowExceptionForHR(((delegate* unmanaged[Stdcall]<nint, int>)Table(_engine)[8])(_engine));
        else
            ((delegate* unmanaged[Stdcall]<nint, void>)Table(_engine)[9])(_engine);
        _running = running;
    }

    public void SetVolume(int percent) => Marshal.ThrowExceptionForHR(
        ((delegate* unmanaged[Stdcall]<nint, float, uint, int>)Table(_master)[12])(_master, percent / 100f, 0));

    public static void Play(nint voice, nint data, int length)
    {
        var buffer = new AudioBuffer { Flags = 0x40, AudioBytes = (uint)length, AudioData = data };
        Marshal.ThrowExceptionForHR(((delegate* unmanaged[Stdcall]<nint, AudioBuffer*, nint, int>)Table(voice)[21])(voice, &buffer, 0));
        Marshal.ThrowExceptionForHR(((delegate* unmanaged[Stdcall]<nint, uint, uint, int>)Table(voice)[19])(voice, 0, 0));
    }

    public static uint QueuedBuffers(nint voice)
    {
        VoiceState state;
        ((delegate* unmanaged[Stdcall]<nint, VoiceState*, uint, void>)Table(voice)[25])(voice, &state, 0x100);
        return state.BuffersQueued;
    }

    public static void Stop(nint voice)
    {
        Marshal.ThrowExceptionForHR(((delegate* unmanaged[Stdcall]<nint, uint, uint, int>)Table(voice)[20])(voice, 0, 0));
        Marshal.ThrowExceptionForHR(((delegate* unmanaged[Stdcall]<nint, int>)Table(voice)[22])(voice));
    }

    public static void DestroyVoice(nint voice) => ((delegate* unmanaged[Stdcall]<nint, void>)Table(voice)[18])(voice);
    private static nint* Table(nint instance) => *(nint**)instance;

    public void Dispose()
    {
        if (_master != 0)
        { DestroyVoice(_master); _master = 0; }
        if (_engine != 0)
        {
            ((delegate* unmanaged[Stdcall]<nint, uint>)Table(_engine)[2])(_engine);
            _engine = 0;
        }
        if (_comInitialized)
        { CoUninitialize(); _comInitialized = false; }
    }

    // xaudio2.h uses pack(1), including pointers and the 64-bit sample counter.
    [StructLayout(LayoutKind.Sequential, Pack = 1)]
    private struct WaveFormat
    {
        public ushort FormatTag, Channels;
        public uint SamplesPerSecond, AverageBytesPerSecond;
        public ushort BlockAlign, BitsPerSample, ExtraSize;
    }
    [StructLayout(LayoutKind.Sequential, Pack = 1)]
    private struct AudioBuffer
    {
        public uint Flags, AudioBytes;
        public nint AudioData;
        public uint PlayBegin, PlayLength, LoopBegin, LoopLength, LoopCount;
        public nint Context;
    }
    [StructLayout(LayoutKind.Sequential, Pack = 1)]
    private struct VoiceState
    {
        public nint Context;
        public uint BuffersQueued;
        public ulong SamplesPlayed;
    }

    [DllImport("xaudio2_9.dll", ExactSpelling = true)] private static extern int XAudio2Create(out nint engine, uint flags, uint processor);
    [DllImport("ole32.dll")] private static extern int CoInitializeEx(nint reserved, uint apartment);
    [DllImport("ole32.dll")] private static extern void CoUninitialize();
}
