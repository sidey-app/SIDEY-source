using System.Runtime.InteropServices;
using Sidey.Core.Domain;

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
    internal const uint NoRepeat = 0x4000;
    private readonly nint _window;
    private readonly ITrayHotkeyNative _native;
    private readonly Dictionary<int, TrayCommand> _registered = [];

    internal TrayHotkeys(
        nint window,
        GlobalHotkeySettings settings,
        ITrayHotkeyNative? native = null)
    {
        _window = window;
        _native = native ?? new WindowsHotkeyNative();
        Settings = settings.Normalize();
        var failures = new List<TrayHotkeyFailure>();
        foreach (TrayCommand command in Commands)
        {
            GlobalHotkeyBinding binding = Settings.BindingFor(Action(command));
            if (binding.IsDisabled)
                continue;
            int error = _native.Register(
                window,
                (int)command,
                (uint)binding.Modifiers | NoRepeat,
                binding.VirtualKey);
            if (error == 0)
            {
                _registered.Add((int)command, command);
            }
            else
            {
                failures.Add(new TrayHotkeyFailure(Shortcut(command, Settings), error));
            }
        }
        Failures = failures.AsReadOnly();
    }

    internal IReadOnlyList<TrayHotkeyFailure> Failures { get; }

    internal GlobalHotkeySettings Settings { get; }

    internal static TrayCommand[] Commands =>
    [
        TrayCommand.ToggleOverlay,
        TrayCommand.ToggleQuietMode,
        TrayCommand.Compose,
        TrayCommand.History,
    ];

    internal bool TryGetCommand(nint id, out TrayCommand command) =>
        _registered.TryGetValue((int)id, out command);

    internal static GlobalHotkeyAction Action(TrayCommand command) => command switch
    {
        TrayCommand.ToggleOverlay => GlobalHotkeyAction.ToggleOverlay,
        TrayCommand.ToggleQuietMode => GlobalHotkeyAction.ToggleQuietMode,
        TrayCommand.Compose => GlobalHotkeyAction.Compose,
        TrayCommand.History => GlobalHotkeyAction.History,
        _ => throw new ArgumentOutOfRangeException(nameof(command)),
    };

    internal static string Shortcut(TrayCommand command, GlobalHotkeySettings settings) =>
        Commands.Contains(command)
            ? settings.Normalize().BindingFor(Action(command)).ToDisplayText().Replace(" + ", "+", StringComparison.Ordinal)
            : string.Empty;

    internal static uint VirtualKey(TrayCommand command, GlobalHotkeySettings settings) =>
        settings.Normalize().BindingFor(Action(command)).VirtualKey;

    internal static string MenuLabel(
        TrayCommand command,
        string label,
        GlobalHotkeySettings settings)
    {
        string shortcut = Shortcut(command, settings);
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
