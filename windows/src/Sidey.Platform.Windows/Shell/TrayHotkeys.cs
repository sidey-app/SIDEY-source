using System.Runtime.InteropServices;

namespace Sidey.Platform.Windows.Shell;

internal sealed record TrayHotkeyFailure(string Shortcut, int ErrorCode);

internal interface ITrayHotkeyNative
{
    public int Register(nint window, int id, uint modifiers, uint virtualKey);
    public void Unregister(nint window, int id);
}

// The tray thread owns both registration and disposal. No keyboard hook is needed.
internal sealed class TrayHotkeys : IDisposable
{
    internal const uint Message = 0x0312; // WM_HOTKEY
    internal const uint Modifiers = 0x0001 | 0x0002 | 0x4000; // ALT | CONTROL | NOREPEAT
    private static readonly (TrayCommand Command, uint Key)[] s_bindings =
    [
        (TrayCommand.ToggleQuietMode, 'M'),
        (TrayCommand.Compose, 'I'),
        (TrayCommand.History, 'R'),
    ];

    private readonly nint _window;
    private readonly ITrayHotkeyNative _native;
    private readonly Dictionary<int, TrayCommand> _registered = [];

    internal TrayHotkeys(nint window, ITrayHotkeyNative? native = null)
    {
        _window = window;
        _native = native ?? new WindowsHotkeyNative();
        var failures = new List<TrayHotkeyFailure>();
        foreach ((TrayCommand command, uint key) in s_bindings)
        {
            int error = _native.Register(window, (int)command, Modifiers, key);
            if (error == 0)
            {
                _registered.Add((int)command, command);
            }
            else
            {
                failures.Add(new TrayHotkeyFailure(Shortcut(command), error));
            }
        }
        Failures = failures.AsReadOnly();
    }

    internal IReadOnlyList<TrayHotkeyFailure> Failures { get; }

    internal bool TryGetCommand(nint id, out TrayCommand command) =>
        _registered.TryGetValue((int)id, out command);

    internal static string Shortcut(TrayCommand command) => command switch
    {
        TrayCommand.ToggleQuietMode => "Ctrl+Alt+M",
        TrayCommand.Compose => "Ctrl+Alt+I",
        TrayCommand.History => "Ctrl+Alt+R",
        _ => string.Empty,
    };

    internal static string MenuLabel(TrayCommand command, string label)
    {
        string shortcut = Shortcut(command);
        return shortcut.Length > 0 ? $"{label}\t{shortcut}" : label;
    }

    public void Dispose()
    {
        foreach (int id in _registered.Keys)
        {
            _native.Unregister(_window, id);
        }
        _registered.Clear();
    }

    private sealed class WindowsHotkeyNative : ITrayHotkeyNative
    {
        public int Register(nint window, int id, uint modifiers, uint virtualKey) =>
            RegisterHotKey(window, id, modifiers, virtualKey) ? 0 : Marshal.GetLastPInvokeError();

        public void Unregister(nint window, int id) => UnregisterHotKey(window, id);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool RegisterHotKey(nint window, int id, uint modifiers, uint virtualKey);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool UnregisterHotKey(nint window, int id);
    }
}
