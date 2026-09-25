using System.ComponentModel;
using System.Runtime.InteropServices;
using Sidey.Core.Domain;

namespace Sidey.Platform.Windows.Shell;

/// <summary>Records keys only while SIDEY's focused shortcut editor is in front.</summary>
public sealed class WindowsFocusedHotkeyRecorder : IDisposable
{
    private const int LowLevelKeyboardHook = 13;
    private const uint KeyDown = 0x0100;
    private const uint KeyUp = 0x0101;
    private const uint SystemKeyDown = 0x0104;
    private const uint SystemKeyUp = 0x0105;
    private const int ErrorInvalidHookHandle = 1404;
    private static readonly Lock s_orphanGate = new();
    private static readonly List<WindowsFocusedHotkeyRecorder> s_orphanedHooks = [];

    private readonly nint _window;
    private readonly Func<bool> _isEditorFocused;
    private readonly Action<uint, GlobalHotkeyModifiers> _record;
    private readonly HookProcedure _procedure;
    private readonly HashSet<uint> _consumedKeys = [];
    private readonly HashSet<uint> _pressedModifierKeys = [];
    private nint _hook;
    private bool _disposed;

    public WindowsFocusedHotkeyRecorder(
        nint window,
        Func<bool> isEditorFocused,
        Action<uint, GlobalHotkeyModifiers> record)
    {
        if (window == nint.Zero)
            throw new ArgumentException("A valid window handle is required.", nameof(window));
        _window = window;
        _isEditorFocused = isEditorFocused;
        _record = record;
        _procedure = KeyboardProcedure;
        RetryOrphanedHooks();
    }

    public bool IsActive => _hook != nint.Zero;
    public GlobalHotkeyModifiers PressedModifiers => ModifiersFor(_pressedModifierKeys);

    public void SetActive(bool active)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        if (active && _hook == nint.Zero)
        {
            _pressedModifierKeys.Clear();
            _pressedModifierKeys.UnionWith(PhysicalModifierKeys());
            _hook = SetWindowsHookEx(
                LowLevelKeyboardHook, _procedure, GetModuleHandle(null), 0);
            if (_hook == nint.Zero)
                throw new Win32Exception(Marshal.GetLastWin32Error());
        }
        else if (!active && _hook != nint.Zero)
        {
            if (!HookReleased(_hook))
                throw new Win32Exception(Marshal.GetLastWin32Error());
            _hook = nint.Zero;
            _consumedKeys.Clear();
        }
    }

    public void Dispose()
    {
        if (_disposed)
            return;
        _disposed = true;
        if (_hook != nint.Zero)
        {
            if (HookReleased(_hook))
            {
                _hook = nint.Zero;
            }
            else
            {
                // Keep the callback alive if Windows did not release the hook.
                lock (s_orphanGate)
                    s_orphanedHooks.Add(this);
            }
        }
        GC.KeepAlive(_procedure);
    }

    private nint KeyboardProcedure(int code, nuint message, nint data)
    {
        if (_disposed || code < 0 || _window != GetForegroundWindow())
            return CallNextHookEx(_hook, code, message, data);

        bool editorFocused;
        try
        {
            editorFocused = _isEditorFocused();
        }
        catch (Exception)
        {
            return CallNextHookEx(_hook, code, message, data);
        }
        if (!ShouldRecord(_window, _window, editorFocused))
            return CallNextHookEx(_hook, code, message, data);

        uint keyMessage = (uint)message;
        if (keyMessage is not (KeyDown or KeyUp or SystemKeyDown or SystemKeyUp))
            return CallNextHookEx(_hook, code, message, data);
        if (data == nint.Zero)
            return CallNextHookEx(_hook, code, message, data);

        // Read the virtual key only after confirming that this editor owns focus.
        uint virtualKey = NormalizeModifierKey(
            unchecked((uint)Marshal.ReadInt32(data)),
            unchecked((uint)Marshal.ReadInt32(data, 4)),
            unchecked((uint)Marshal.ReadInt32(data, 8)));
        if (keyMessage is KeyDown or SystemKeyDown)
        {
            GlobalHotkeyModifiers modifiers = ApplyKeyTransition(
                _pressedModifierKeys, virtualKey, down: true);
            if (ShouldPassThrough(virtualKey, modifiers)
                || ShouldForwardModifier(virtualKey))
                return CallNextHookEx(_hook, code, message, data);
            try
            {
                _record(virtualKey, modifiers);
            }
            catch (Exception)
            {
                return CallNextHookEx(_hook, code, message, data);
            }
            _consumedKeys.Add(virtualKey);
            return 1;
        }

        _ = ApplyKeyTransition(_pressedModifierKeys, virtualKey, down: false);
        // A key pressed before the editor gained focus must also be released to Windows.
        return _consumedKeys.Remove(virtualKey)
            ? 1
            : CallNextHookEx(_hook, code, message, data);
    }

    internal static bool ShouldRecord(nint window, nint foreground, bool editorFocused) =>
        window != nint.Zero && window == foreground && editorFocused;

    public static bool ShouldPassThrough(uint virtualKey, GlobalHotkeyModifiers modifiers) =>
        virtualKey == 0x09 && (modifiers & ~GlobalHotkeyModifiers.Shift) == 0;

    internal static GlobalHotkeyModifiers ModifierFor(uint virtualKey) => virtualKey switch
    {
        0x11 or 0xA2 or 0xA3 => GlobalHotkeyModifiers.Control,
        0x12 or 0xA4 or 0xA5 => GlobalHotkeyModifiers.Alt,
        0x10 or 0xA0 or 0xA1 => GlobalHotkeyModifiers.Shift,
        0x5B or 0x5C => GlobalHotkeyModifiers.Windows,
        _ => GlobalHotkeyModifiers.None,
    };

    internal static GlobalHotkeyModifiers ApplyKeyTransition(
        HashSet<uint> pressedKeys,
        uint virtualKey,
        bool down)
    {
        if (ModifierFor(virtualKey) != GlobalHotkeyModifiers.None)
        {
            if (down)
                pressedKeys.Add(virtualKey);
            else
                pressedKeys.Remove(virtualKey);
        }
        return ModifiersFor(pressedKeys);
    }

    private static GlobalHotkeyModifiers ModifiersFor(IEnumerable<uint> pressedKeys)
    {
        GlobalHotkeyModifiers modifiers = GlobalHotkeyModifiers.None;
        foreach (uint key in pressedKeys)
            modifiers |= ModifierFor(key);
        return modifiers;
    }

    private static HashSet<uint> PhysicalModifierKeys()
    {
        var keys = new HashSet<uint>();
        foreach (uint key in new uint[] { 0xA0, 0xA1, 0xA2, 0xA3, 0xA4, 0xA5, 0x5B, 0x5C })
        {
            if (IsDown((int)key))
                keys.Add(key);
        }
        return keys;
    }

    internal static uint NormalizeModifierKey(uint virtualKey, uint scanCode, uint flags) =>
        virtualKey switch
        {
            0x10 => scanCode == 0x36 ? 0xA1u : 0xA0u,
            0x11 => (flags & 1) != 0 ? 0xA3u : 0xA2u,
            0x12 => (flags & 1) != 0 ? 0xA5u : 0xA4u,
            _ => virtualKey,
        };

    private static bool ShouldForwardModifier(uint virtualKey) =>
        ModifierFor(virtualKey) is GlobalHotkeyModifiers.Control
            or GlobalHotkeyModifiers.Alt or GlobalHotkeyModifiers.Shift;

    private static bool HookReleased(nint hook) =>
        UnhookWindowsHookEx(hook) || Marshal.GetLastWin32Error() == ErrorInvalidHookHandle;

    private static void RetryOrphanedHooks()
    {
        lock (s_orphanGate)
        {
            for (int index = s_orphanedHooks.Count - 1; index >= 0; index--)
            {
                WindowsFocusedHotkeyRecorder orphan = s_orphanedHooks[index];
                if (HookReleased(orphan._hook))
                {
                    orphan._hook = nint.Zero;
                    s_orphanedHooks.RemoveAt(index);
                }
            }
        }
    }

    private static bool IsDown(int virtualKey) => (GetAsyncKeyState(virtualKey) & 0x8000) != 0;

    [UnmanagedFunctionPointer(CallingConvention.Winapi)]
    private delegate nint HookProcedure(int code, nuint message, nint data);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern nint SetWindowsHookEx(int idHook, HookProcedure procedure, nint module, uint threadId);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool UnhookWindowsHookEx(nint hook);

    [DllImport("user32.dll")]
    private static extern nint CallNextHookEx(nint hook, int code, nuint message, nint data);

    [DllImport("user32.dll")]
    private static extern nint GetForegroundWindow();

    [DllImport("user32.dll")]
    private static extern short GetAsyncKeyState(int virtualKey);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    private static extern nint GetModuleHandle(string? moduleName);
}
