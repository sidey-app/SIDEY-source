using Sidey.Core.Domain;

namespace Sidey.Core.Tests;

public sealed class GlobalHotkeySettingsTests
{
    [Fact]
    public void DefaultsCoverAllFourActionsWithUniqueBindings()
    {
        GlobalHotkeySettings settings = GlobalHotkeySettings.Default;

        Assert.Equal(GlobalHotkeyKey.H, settings.ToggleOverlay);
        Assert.Equal(GlobalHotkeyKey.M, settings.ToggleQuietMode);
        Assert.Equal(GlobalHotkeyKey.I, settings.Compose);
        Assert.Equal(GlobalHotkeyKey.R, settings.History);
        Assert.Equal(
            new GlobalHotkeyBinding(GlobalHotkeyModifiers.Control | GlobalHotkeyModifiers.Alt, 'H'),
            settings.BindingFor(GlobalHotkeyAction.ToggleOverlay));
        Assert.Equal(4, Enum.GetValues<GlobalHotkeyAction>()
            .Select(settings.BindingFor)
            .Distinct()
            .Count());
    }

    [Fact]
    public void AssigningAnOccupiedKeySwapsTheTwoActions()
    {
        GlobalHotkeySettings settings = GlobalHotkeySettings.Default.Assign(
            GlobalHotkeyAction.ToggleOverlay,
            GlobalHotkeyKey.I);

        Assert.Equal(GlobalHotkeyKey.I, settings.ToggleOverlay);
        Assert.Equal(GlobalHotkeyKey.H, settings.Compose);
        Assert.Equal(GlobalHotkeyKey.M, settings.ToggleQuietMode);
        Assert.Equal(GlobalHotkeyKey.R, settings.History);
    }

    [Fact]
    public void InvalidOrDuplicatePersistedMappingsReturnToDefaults()
    {
        Assert.Equal(
            GlobalHotkeySettings.Default,
            new GlobalHotkeySettings(
                (GlobalHotkeyKey)99,
                GlobalHotkeyKey.M,
                GlobalHotkeyKey.I,
                GlobalHotkeyKey.R).Normalize());
        Assert.Equal(
            GlobalHotkeySettings.Default,
            new GlobalHotkeySettings(
                GlobalHotkeyKey.H,
                GlobalHotkeyKey.H,
                GlobalHotkeyKey.I,
                GlobalHotkeyKey.R).Normalize());
    }

    [Fact]
    public void LegacyMappingsHydrateToControlAltBindings()
    {
        var legacy = new GlobalHotkeySettings(
            GlobalHotkeyKey.O,
            GlobalHotkeyKey.Q,
            GlobalHotkeyKey.C,
            GlobalHotkeyKey.L);

        GlobalHotkeySettings normalized = legacy.Normalize();

        Assert.Equal(
            new GlobalHotkeyBinding(GlobalHotkeyModifiers.Control | GlobalHotkeyModifiers.Alt, 'O'),
            normalized.BindingFor(GlobalHotkeyAction.ToggleOverlay));
        Assert.NotNull(normalized.ToggleOverlayBinding);
    }

    [Fact]
    public void AssigningAnOccupiedCompleteBindingSwapsTheTwoActions()
    {
        var custom = new GlobalHotkeyBinding(
            GlobalHotkeyModifiers.Control | GlobalHotkeyModifiers.Shift,
            0x74); // F5
        GlobalHotkeySettings starting = GlobalHotkeySettings.Default
            .Assign(GlobalHotkeyAction.Compose, custom);

        GlobalHotkeySettings assigned = starting.Assign(
            GlobalHotkeyAction.ToggleOverlay,
            custom);

        Assert.Equal(custom, assigned.BindingFor(GlobalHotkeyAction.ToggleOverlay));
        Assert.Equal(
            GlobalHotkeyBinding.FromLegacy(GlobalHotkeyKey.H),
            assigned.BindingFor(GlobalHotkeyAction.Compose));
    }

    [Theory]
    [InlineData(0x74u, "Ctrl + Shift + F5")]
    [InlineData(0x31u, "Ctrl + Shift + 1")]
    [InlineData(0x25u, "Ctrl + Shift + Left")]
    public void BindingFormatsCommonKeyboardKeys(uint virtualKey, string expected)
    {
        var binding = new GlobalHotkeyBinding(
            GlobalHotkeyModifiers.Control | GlobalHotkeyModifiers.Shift,
            virtualKey);

        Assert.True(binding.IsValid());
        Assert.Equal(expected, binding.ToDisplayText());
    }

    [Fact]
    public void BindingRequiresAModifierAndANonModifierKey()
    {
        Assert.False(new GlobalHotkeyBinding(GlobalHotkeyModifiers.None, 'A').IsValid());
        Assert.False(new GlobalHotkeyBinding(GlobalHotkeyModifiers.Control, 0x11).IsValid());
        Assert.True(new GlobalHotkeyBinding(GlobalHotkeyModifiers.Windows, 'A').IsValid());
    }

    [Fact]
    public void DeletedShortcutsStayDisabledAfterNormalizationAndCanBeRestored()
    {
        GlobalHotkeySettings settings = GlobalHotkeySettings.Default
            .Assign(GlobalHotkeyAction.Compose, GlobalHotkeyBinding.Disabled)
            .Assign(GlobalHotkeyAction.History, GlobalHotkeyBinding.Disabled)
            .Normalize();

        Assert.True(settings.BindingFor(GlobalHotkeyAction.Compose).IsDisabled);
        Assert.True(settings.BindingFor(GlobalHotkeyAction.History).IsDisabled);
        Assert.Equal(string.Empty, settings.BindingFor(GlobalHotkeyAction.Compose).ToDisplayText());

        GlobalHotkeySettings restored = settings.Assign(
            GlobalHotkeyAction.Compose,
            GlobalHotkeySettings.Default.BindingFor(GlobalHotkeyAction.Compose));
        Assert.False(restored.BindingFor(GlobalHotkeyAction.Compose).IsDisabled);
        Assert.True(restored.BindingFor(GlobalHotkeyAction.History).IsDisabled);
    }
}
