using Sidey.Core.Domain;
using Sidey.Platform.Windows.Shell;

namespace Sidey.Platform.Windows.Tests;

public sealed class WindowsFocusedHotkeyRecorderTests
{
    [Fact]
    public void RecorderAcceptsOnlyFocusedSideyWindow()
    {
        Assert.True(WindowsFocusedHotkeyRecorder.ShouldRecord(1, 1, editorFocused: true));
        Assert.False(WindowsFocusedHotkeyRecorder.ShouldRecord(1, 2, editorFocused: true));
        Assert.False(WindowsFocusedHotkeyRecorder.ShouldRecord(1, 1, editorFocused: false));
        Assert.False(WindowsFocusedHotkeyRecorder.ShouldRecord(0, 0, editorFocused: true));
    }

    [Fact]
    public void RecorderKeepsTabNavigationAndCapturesWindowsScreenSnipping()
    {
        Assert.True(WindowsFocusedHotkeyRecorder.ShouldPassThrough(
            0x09, GlobalHotkeyModifiers.None));
        Assert.True(WindowsFocusedHotkeyRecorder.ShouldPassThrough(
            0x09, GlobalHotkeyModifiers.Shift));
        Assert.False(WindowsFocusedHotkeyRecorder.ShouldPassThrough(
            'S', GlobalHotkeyModifiers.Windows | GlobalHotkeyModifiers.Shift));
    }

    [Fact]
    public void SuppressedModifierKeyDownsStillBuildTheScreenSnippingChord()
    {
        var pressedKeys = new HashSet<uint>();
        _ = WindowsFocusedHotkeyRecorder.ApplyKeyTransition(pressedKeys, 0x5B, down: true);
        _ = WindowsFocusedHotkeyRecorder.ApplyKeyTransition(pressedKeys, 0xA0, down: true);
        GlobalHotkeyModifiers pressed = WindowsFocusedHotkeyRecorder.ApplyKeyTransition(
            pressedKeys, 'S', down: true);
        Assert.Equal(GlobalHotkeyModifiers.Windows | GlobalHotkeyModifiers.Shift, pressed);
        Assert.Equal(
            WindowsHotkeyAvailabilityResult.SystemShortcut,
            WindowsHotkeyAvailability.Check(new GlobalHotkeyBinding(pressed, 'S')));

        pressed = WindowsFocusedHotkeyRecorder.ApplyKeyTransition(
            pressedKeys, 0xA0, down: false);
        Assert.Equal(GlobalHotkeyModifiers.Windows, pressed);
    }

    [Fact]
    public void ReleasingOneOfTwoShiftKeysKeepsShiftPressed()
    {
        var pressedKeys = new HashSet<uint>();
        _ = WindowsFocusedHotkeyRecorder.ApplyKeyTransition(pressedKeys, 0xA0, down: true);
        _ = WindowsFocusedHotkeyRecorder.ApplyKeyTransition(pressedKeys, 0xA1, down: true);

        Assert.Equal(GlobalHotkeyModifiers.Shift,
            WindowsFocusedHotkeyRecorder.ApplyKeyTransition(pressedKeys, 0xA0, down: false));
        Assert.Equal(GlobalHotkeyModifiers.None,
            WindowsFocusedHotkeyRecorder.ApplyKeyTransition(pressedKeys, 0xA1, down: false));
    }

    [Fact]
    public void GenericModifierEventsKeepTheirPhysicalSide()
    {
        Assert.Equal(0xA0u, WindowsFocusedHotkeyRecorder.NormalizeModifierKey(0x10, 0x2A, 0));
        Assert.Equal(0xA1u, WindowsFocusedHotkeyRecorder.NormalizeModifierKey(0x10, 0x36, 0));
        Assert.Equal(0xA3u, WindowsFocusedHotkeyRecorder.NormalizeModifierKey(0x11, 0, 1));
        Assert.Equal(0xA5u, WindowsFocusedHotkeyRecorder.NormalizeModifierKey(0x12, 0, 1));
    }
}
