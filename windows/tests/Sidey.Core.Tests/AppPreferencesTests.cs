using System.Text.Json;
using System.Text.Json.Nodes;
using Sidey.Core.Domain;

namespace Sidey.Core.Tests;

public sealed class AppPreferencesTests
{
    [Theory]
    [InlineData("ko-KR", "ko-KR")]
    [InlineData("en-US", "en-US")]
    [InlineData("ja-JP", "ja-JP")]
    [InlineData("zh-CN", "zh-CN")]
    [InlineData("zh-TW", "zh-TW")]
    [InlineData("uk-UA", "uk-UA")]
    [InlineData("ru-RU", "ru-RU")]
    [InlineData("invalid", null)]
    [InlineData(null, null)]
    public void LanguagePreferenceOnlyKeepsSupportedCatalogs(string? requested, string? expected)
    {
        Assert.Equal(expected, (AppPreferences.Default with { Language = requested }).Normalize().Language);
    }

    [Fact]
    public void DefaultContainsEveryPersistedWindowsSettingAndStartupStaysOff()
    {
        var preferences = AppPreferences.CreateDefault(1234);

        Assert.Equal(AppPreferences.CurrentSchemaVersion, preferences.SchemaVersion);
        Assert.False(preferences.OnboardingCompleted);
        Assert.Equal(1234, preferences.InstallationSeed);
        Assert.True(preferences.OverlayVisible);
        Assert.False(preferences.QuietMode);
        Assert.True(preferences.ShowOfflineMembers);
        Assert.False(preferences.RequiresRightClickToThrow);
        Assert.False(preferences.StartAtLogin);
        Assert.Null(preferences.Language);
        Assert.Equal(AppThemePreference.System, preferences.Theme);
        Assert.Null(preferences.CachedNickname);
        Assert.Null(preferences.CachedCharacterId);
        Assert.Null(preferences.ActiveRoomId);
        Assert.Null(preferences.ComposerPlacement);
        Assert.Equal(OverlayRegionPreference.Default, preferences.OverlayRegion);
    }

    [Theory]
    [InlineData(AppThemePreference.System, AppThemePreference.System)]
    [InlineData(AppThemePreference.Light, AppThemePreference.Light)]
    [InlineData(AppThemePreference.Dark, AppThemePreference.Dark)]
    [InlineData((AppThemePreference)99, AppThemePreference.System)]
    public void ThemePreferenceOnlyKeepsSupportedValues(
        AppThemePreference requested,
        AppThemePreference expected)
    {
        Assert.Equal(expected, (AppPreferences.Default with { Theme = requested }).Normalize().Theme);
    }

    [Fact]
    public void ComposerPlacementPersistsWithoutChangingOlderSettings()
    {
        AppPreferences saved = AppPreferences.Default with { ComposerPlacement = new ComposerPlacement("secondary", 120, 240) };

        AppPreferences restored = JsonSerializer.Deserialize<AppPreferences>(JsonSerializer.Serialize(saved))!.Normalize();

        Assert.Equal(saved, restored);
    }

    [Fact]
    public void SettingsWithoutComposerPlacementRemainCompatible()
    {
        JsonObject json = JsonSerializer.SerializeToNode(AppPreferences.Default)!.AsObject();
        json.Remove(nameof(AppPreferences.ComposerPlacement));

        AppPreferences restored = json.Deserialize<AppPreferences>()!.Normalize();

        Assert.Equal(AppPreferences.Default, restored);
        Assert.Null(restored.ComposerPlacement);
    }

    [Fact]
    public void InvalidComposerPlacementIsDiscardedDuringNormalization()
    {
        AppPreferences saved = AppPreferences.Default with { ComposerPlacement = new ComposerPlacement("primary", double.NaN, 20) };

        Assert.Null(saved.Normalize().ComposerPlacement);
    }
}
