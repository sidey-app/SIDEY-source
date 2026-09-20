using Sidey.Core.Localization;

namespace Sidey.Core.Domain;

public enum AppThemePreference
{
    System = 0,
    Light = 1,
    Dark = 2,
}

public sealed record AppPreferences(
    int SchemaVersion,
    bool OnboardingCompleted,
    long InstallationSeed,
    bool OverlayVisible,
    bool QuietMode,
    bool ShowOfflineMembers,
    bool RequiresRightClickToThrow,
    bool StartAtLogin,
    string? CachedNickname,
    string? CachedCharacterId,
    Guid? ActiveRoomId,
    OverlayRegionPreference OverlayRegion)
{
    public bool TreeMovementPaused { get; init; }

    public ComposerPlacement? ComposerPlacement { get; init; }

    public string? Language { get; init; }

    public AppThemePreference Theme { get; init; } = AppThemePreference.System;

    public bool CharacterSoundEffectsEnabled { get; init; } = true;
    public int CharacterSoundEffectsVolume { get; init; } = 100;

    public const int CurrentSchemaVersion = 5;

    public static AppPreferences CreateDefault(long? installationSeed = null) => new(
        SchemaVersion: CurrentSchemaVersion,
        OnboardingCompleted: false,
        InstallationSeed: installationSeed ?? Random.Shared.NextInt64(),
        OverlayVisible: true,
        QuietMode: false,
        ShowOfflineMembers: true,
        RequiresRightClickToThrow: false,
        StartAtLogin: false,
        CachedNickname: null,
        CachedCharacterId: null,
        ActiveRoomId: null,
        OverlayRegion: OverlayRegionPreference.Default);

    public static AppPreferences Default { get; } = CreateDefault(0x51DE7);

    public AppPreferences Normalize() => this with
    {
        SchemaVersion = CurrentSchemaVersion,
        CharacterSoundEffectsVolume = Math.Clamp(CharacterSoundEffectsVolume, 0, 100),
        CharacterSoundEffectsEnabled = CharacterSoundEffectsEnabled && CharacterSoundEffectsVolume > 0,
        Language = I18n.IsSupportedLanguage(Language) ? Language : null,
        Theme = Enum.IsDefined(Theme) ? Theme : AppThemePreference.System,
        InstallationSeed = InstallationSeed == 0 ? Random.Shared.NextInt64() : InstallationSeed,
        CachedNickname = CachedNickname is not null && ProfileValidator.IsValidNickname(CachedNickname)
            ? ProfileValidator.NormalizeNickname(CachedNickname)
            : null,
        CachedCharacterId = string.IsNullOrWhiteSpace(CachedCharacterId)
            ? null
            : PixelCharacterCatalog.NormalizeId(CachedCharacterId),
        OverlayRegion = OverlayRegion ?? OverlayRegionPreference.Default,
        ComposerPlacement = ComposerPlacement?.Normalize(),
    };
}
