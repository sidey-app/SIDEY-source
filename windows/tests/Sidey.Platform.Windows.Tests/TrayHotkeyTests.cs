using Sidey.Core.Domain;

namespace Sidey.Platform.Windows.Tests;

public sealed class TrayHotkeyTests
{
    [Fact]
    public void RegisteredShortcutsDispatchTheirCommandsWithoutKeyRepeat()
    {
        var native = new FakeHotkeyNative();
        using var hotkeys = new TrayHotkeys(42, GlobalHotkeySettings.Default, native);

        Assert.Empty(hotkeys.Failures);
        Assert.Collection(
            native.Registrations,
            binding => AssertBinding(binding, TrayCommand.ToggleOverlay, 'H'),
            binding => AssertBinding(binding, TrayCommand.ToggleQuietMode, 'M'),
            binding => AssertBinding(binding, TrayCommand.Compose, 'I'),
            binding => AssertBinding(binding, TrayCommand.History, 'R'));
        foreach ((nint _, int id, uint _, uint _) in native.Registrations)
        {
            Assert.True(hotkeys.TryGetCommand(id, out TrayCommand command));
            Assert.Equal((TrayCommand)id, command);
        }
        Assert.False(hotkeys.TryGetCommand(9999, out _));
    }

    [Fact]
    public void ConflictingShortcutLeavesOtherShortcutsUsableAndReportsTheConflict()
    {
        var native = new FakeHotkeyNative { ConflictingId = (int)TrayCommand.Compose };
        using var hotkeys = new TrayHotkeys(42, GlobalHotkeySettings.Default, native);

        TrayHotkeyFailure failure = Assert.Single(hotkeys.Failures);
        Assert.Equal("Ctrl+Alt+I", failure.Shortcut);
        Assert.Equal(1409, failure.ErrorCode);
        Assert.False(hotkeys.TryGetCommand((int)TrayCommand.Compose, out _));
        Assert.True(hotkeys.TryGetCommand((int)TrayCommand.ToggleQuietMode, out _));
        Assert.True(hotkeys.TryGetCommand((int)TrayCommand.ToggleOverlay, out _));
        Assert.True(hotkeys.TryGetCommand((int)TrayCommand.History, out _));
    }

    [Fact]
    public void DisposalUnregistersOnlyOwnedShortcutsOnceAndStopsDispatch()
    {
        var native = new FakeHotkeyNative { ConflictingId = (int)TrayCommand.Compose };
        var hotkeys = new TrayHotkeys(42, GlobalHotkeySettings.Default, native);

        hotkeys.Dispose();
        hotkeys.Dispose();

        Assert.Equal(
            [
                ((nint)42, (int)TrayCommand.ToggleOverlay),
                ((nint)42, (int)TrayCommand.ToggleQuietMode),
                ((nint)42, (int)TrayCommand.History),
            ],
            native.Unregistrations);
        Assert.False(hotkeys.TryGetCommand((int)TrayCommand.ToggleQuietMode, out _));
        Assert.False(hotkeys.TryGetCommand((int)TrayCommand.History, out _));
    }

    [Theory]
    [InlineData(TrayCommand.ToggleOverlay, "Quiet mode\tCtrl+Alt+H")]
    [InlineData(TrayCommand.ToggleQuietMode, "Quiet mode\tCtrl+Alt+M")]
    [InlineData(TrayCommand.Compose, "Quiet mode\tCtrl+Alt+I")]
    [InlineData(TrayCommand.History, "Quiet mode\tCtrl+Alt+R")]
    [InlineData(TrayCommand.Settings, "Quiet mode")]
    public void TrayMenuShowsTheShortcutBesideItsExistingLabel(TrayCommand command, string expected)
    {
        Assert.Equal(expected, TrayHotkeys.MenuLabel(
            command,
            "Quiet mode",
            GlobalHotkeySettings.Default));
    }

    [Fact]
    public void CustomMappingsRegisterAllActionsWithTheirSelectedKeys()
    {
        var native = new FakeHotkeyNative();
        var settings = new GlobalHotkeySettings(
            GlobalHotkeyKey.O,
            GlobalHotkeyKey.Q,
            GlobalHotkeyKey.C,
            GlobalHotkeyKey.L);

        using var hotkeys = new TrayHotkeys(42, settings, native);

        Assert.Collection(
            native.Registrations,
            binding => AssertBinding(binding, TrayCommand.ToggleOverlay, 'O'),
            binding => AssertBinding(binding, TrayCommand.ToggleQuietMode, 'Q'),
            binding => AssertBinding(binding, TrayCommand.Compose, 'C'),
            binding => AssertBinding(binding, TrayCommand.History, 'L'));
        Assert.Equal("Ctrl+Alt+O", TrayHotkeys.Shortcut(TrayCommand.ToggleOverlay, settings));
    }

    [Fact]
    public void CompleteShortcutRegistersItsModifiersAndVirtualKey()
    {
        var native = new FakeHotkeyNative();
        GlobalHotkeySettings settings = GlobalHotkeySettings.Default.Assign(
            GlobalHotkeyAction.ToggleOverlay,
            new GlobalHotkeyBinding(
                GlobalHotkeyModifiers.Control | GlobalHotkeyModifiers.Shift | GlobalHotkeyModifiers.Windows,
                0x74));

        using var hotkeys = new TrayHotkeys(42, settings, native);

        (nint Window, int Id, uint Modifiers, uint Key) registration = native.Registrations[0];
        Assert.Equal(0x400Eu, registration.Modifiers);
        Assert.Equal(0x74u, registration.Key);
        Assert.Equal("Ctrl+Shift+Win+F5", TrayHotkeys.Shortcut(TrayCommand.ToggleOverlay, settings));
    }

    [Fact]
    public void DeletedShortcutIsNotRegisteredOrShownInTheTrayMenu()
    {
        var native = new FakeHotkeyNative();
        GlobalHotkeySettings settings = GlobalHotkeySettings.Default.Assign(
            GlobalHotkeyAction.Compose, GlobalHotkeyBinding.Disabled);

        using var hotkeys = new TrayHotkeys(42, settings, native);

        Assert.DoesNotContain(native.Registrations, binding => binding.Id == (int)TrayCommand.Compose);
        Assert.False(hotkeys.TryGetCommand((int)TrayCommand.Compose, out _));
        Assert.Equal("Compose", TrayHotkeys.MenuLabel(TrayCommand.Compose, "Compose", settings));
        Assert.Empty(hotkeys.Failures);
    }

    private static void AssertBinding(
        (nint Window, int Id, uint Modifiers, uint Key) binding,
        TrayCommand command,
        char key)
    {
        Assert.Equal((nint)42, binding.Window);
        Assert.Equal((int)command, binding.Id);
        Assert.Equal(0x4003u, binding.Modifiers);
        Assert.Equal((uint)key, binding.Key);
    }

    private sealed class FakeHotkeyNative : ITrayHotkeyNative
    {
        public int? ConflictingId { get; init; }
        public List<(nint Window, int Id, uint Modifiers, uint Key)> Registrations { get; } = [];
        public List<(nint Window, int Id)> Unregistrations { get; } = [];

        public int Register(nint window, int id, uint modifiers, uint virtualKey)
        {
            Registrations.Add((window, id, modifiers, virtualKey));
            return id == ConflictingId ? 1409 : 0;
        }

        public void Unregister(nint window, int id) => Unregistrations.Add((window, id));
    }
}
