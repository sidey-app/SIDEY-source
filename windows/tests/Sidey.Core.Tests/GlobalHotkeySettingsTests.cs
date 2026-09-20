using Sidey.Core.Domain;

namespace Sidey.Core.Tests;

public sealed class GlobalHotkeySettingsTests
{
    [Fact]
    public void DefaultsCoverAllFourActionsWithUniqueKeys()
    {
        GlobalHotkeySettings settings = GlobalHotkeySettings.Default;

        Assert.Equal(GlobalHotkeyKey.H, settings.ToggleOverlay);
        Assert.Equal(GlobalHotkeyKey.M, settings.ToggleQuietMode);
        Assert.Equal(GlobalHotkeyKey.I, settings.Compose);
        Assert.Equal(GlobalHotkeyKey.R, settings.History);
        Assert.Equal(4, Enum.GetValues<GlobalHotkeyAction>()
            .Select(settings.KeyFor)
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
}
