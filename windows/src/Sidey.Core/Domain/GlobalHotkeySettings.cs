namespace Sidey.Core.Domain;

public enum GlobalHotkeyAction
{
    ToggleOverlay = 0,
    ToggleQuietMode = 1,
    Compose = 2,
    History = 3,
}

public enum GlobalHotkeyKey
{
    A = 0, B, C, D, E, F, G, H, I, J, K, L, M,
    N, O, P, Q, R, S, T, U, V, W, X, Y, Z,
}

public sealed record GlobalHotkeySettings(
    GlobalHotkeyKey ToggleOverlay,
    GlobalHotkeyKey ToggleQuietMode,
    GlobalHotkeyKey Compose,
    GlobalHotkeyKey History)
{
    public static GlobalHotkeySettings Default { get; } = new(
        GlobalHotkeyKey.H,
        GlobalHotkeyKey.M,
        GlobalHotkeyKey.I,
        GlobalHotkeyKey.R);

    public GlobalHotkeySettings Normalize()
    {
        GlobalHotkeyKey[] keys = [ToggleOverlay, ToggleQuietMode, Compose, History];
        return keys.All(Enum.IsDefined) && keys.Distinct().Count() == keys.Length
            ? this
            : Default;
    }

    public GlobalHotkeyKey KeyFor(GlobalHotkeyAction action) => action switch
    {
        GlobalHotkeyAction.ToggleOverlay => ToggleOverlay,
        GlobalHotkeyAction.ToggleQuietMode => ToggleQuietMode,
        GlobalHotkeyAction.Compose => Compose,
        GlobalHotkeyAction.History => History,
        _ => throw new ArgumentOutOfRangeException(nameof(action)),
    };

    public GlobalHotkeySettings Assign(GlobalHotkeyAction action, GlobalHotkeyKey key)
    {
        if (!Enum.IsDefined(key))
            return Normalize();

        GlobalHotkeySettings current = Normalize();
        GlobalHotkeyKey previous = current.KeyFor(action);
        GlobalHotkeyAction? occupied = Enum.GetValues<GlobalHotkeyAction>()
            .Cast<GlobalHotkeyAction?>()
            .FirstOrDefault(candidate => candidate != action && current.KeyFor(candidate!.Value) == key);
        GlobalHotkeySettings assigned = current.Set(action, key);
        return occupied is { } other ? assigned.Set(other, previous) : assigned;
    }

    private GlobalHotkeySettings Set(GlobalHotkeyAction action, GlobalHotkeyKey key) => action switch
    {
        GlobalHotkeyAction.ToggleOverlay => this with { ToggleOverlay = key },
        GlobalHotkeyAction.ToggleQuietMode => this with { ToggleQuietMode = key },
        GlobalHotkeyAction.Compose => this with { Compose = key },
        GlobalHotkeyAction.History => this with { History = key },
        _ => throw new ArgumentOutOfRangeException(nameof(action)),
    };
}
