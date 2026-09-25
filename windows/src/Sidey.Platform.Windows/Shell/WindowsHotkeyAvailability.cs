using Sidey.Core.Domain;

namespace Sidey.Platform.Windows.Shell;

public enum WindowsHotkeyAvailabilityResult
{
    Available,
    SystemShortcut,
    AlreadyRegistered,
    Unverified,
}

public static class WindowsHotkeyAvailability
{
    private const int ProbeId = 0x53DE;
    private const int ErrorHotkeyAlreadyRegistered = 1409;

    public static WindowsHotkeyAvailabilityResult Check(GlobalHotkeyBinding binding) =>
        Check(binding, new WindowsHotkeyNative());

    internal static WindowsHotkeyAvailabilityResult Check(
        GlobalHotkeyBinding binding,
        ITrayHotkeyNative native)
    {
        if (!binding.IsValid())
            return WindowsHotkeyAvailabilityResult.Unverified;

        // Windows handles these before an ordinary app can reliably receive them.
        if (IsSystemShortcut(binding))
            return WindowsHotkeyAvailabilityResult.SystemShortcut;

        // The tray suspends its registrations while the editor is open. A temporary
        // thread hotkey therefore checks Windows and other applications only.
        int error = native.Register(
            nint.Zero,
            ProbeId,
            (uint)binding.Modifiers | TrayHotkeys.NoRepeat,
            binding.VirtualKey);
        if (error == 0)
        {
            native.Unregister(nint.Zero, ProbeId);
            return WindowsHotkeyAvailabilityResult.Available;
        }
        return error == ErrorHotkeyAlreadyRegistered
            ? WindowsHotkeyAvailabilityResult.AlreadyRegistered
            : WindowsHotkeyAvailabilityResult.Unverified;
    }

    internal static bool IsSystemShortcut(GlobalHotkeyBinding binding)
    {
        if (binding.Modifiers == (GlobalHotkeyModifiers.Windows | GlobalHotkeyModifiers.Shift)
            && binding.VirtualKey == 'S')
            return true; // Windows screen snipping

        return binding.Modifiers == GlobalHotkeyModifiers.Windows
            && binding.VirtualKey is 'A' or 'D' or 'E' or 'G' or 'I' or 'K'
                or 'L' or 'P' or 'R' or 'V' or 'X' or 0x09;
    }
}
