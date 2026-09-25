using Sidey.Core.Domain;
using Sidey.Platform.Windows.Shell;

namespace Sidey.Platform.Windows.Tests;

public sealed class WindowsHotkeyAvailabilityTests
{
    [Fact]
    public void WindowsScreenSnippingWarnsWithoutTakingTheShortcut()
    {
        var native = new FakeNative();
        var shortcut = new GlobalHotkeyBinding(
            GlobalHotkeyModifiers.Windows | GlobalHotkeyModifiers.Shift, 'S');

        Assert.Equal(
            WindowsHotkeyAvailabilityResult.SystemShortcut,
            WindowsHotkeyAvailability.Check(shortcut, native));
        Assert.Empty(native.Registrations);
    }

    [Fact]
    public void AvailableShortcutIsReleasedImmediatelyAfterProbe()
    {
        var native = new FakeNative();
        var shortcut = new GlobalHotkeyBinding(
            GlobalHotkeyModifiers.Windows | GlobalHotkeyModifiers.Control, 'O');

        Assert.Equal(
            WindowsHotkeyAvailabilityResult.Available,
            WindowsHotkeyAvailability.Check(shortcut, native));
        Assert.Single(native.Registrations);
        Assert.Equal((nint.Zero, native.Registrations[0].Id), Assert.Single(native.Unregistrations));
        Assert.Equal((uint)shortcut.Modifiers | TrayHotkeys.NoRepeat,
            native.Registrations[0].Modifiers);
        Assert.Equal(shortcut.VirtualKey, native.Registrations[0].VirtualKey);
    }

    [Theory]
    [InlineData(1409, WindowsHotkeyAvailabilityResult.AlreadyRegistered)]
    [InlineData(5, WindowsHotkeyAvailabilityResult.Unverified)]
    public void FailedProbeDoesNotUnregisterAnotherOwnersShortcut(
        int error,
        WindowsHotkeyAvailabilityResult expected)
    {
        var native = new FakeNative { Error = error };
        var shortcut = new GlobalHotkeyBinding(GlobalHotkeyModifiers.Control, 'O');

        Assert.Equal(expected, WindowsHotkeyAvailability.Check(shortcut, native));
        Assert.Empty(native.Unregistrations);
    }

    private sealed class FakeNative : ITrayHotkeyNative
    {
        public int Error { get; init; }
        public List<(nint Window, int Id, uint Modifiers, uint VirtualKey)> Registrations { get; } = [];
        public List<(nint Window, int Id)> Unregistrations { get; } = [];

        public int Register(nint window, int id, uint modifiers, uint virtualKey)
        {
            Registrations.Add((window, id, modifiers, virtualKey));
            return Error;
        }

        public void Unregister(nint window, int id) => Unregistrations.Add((window, id));
    }
}
