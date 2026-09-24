namespace Sidey.Core.Domain;

public enum GlobalHotkeyAction
{
    ToggleOverlay = 0,
    ToggleQuietMode = 1,
    Compose = 2,
    History = 3,
}

// Retained so preferences written by SIDEY 1.4 and earlier continue to load.
public enum GlobalHotkeyKey
{
    A = 0, B, C, D, E, F, G, H, I, J, K, L, M,
    N, O, P, Q, R, S, T, U, V, W, X, Y, Z,
}

[Flags]
public enum GlobalHotkeyModifiers : uint
{
    None = 0,
    Alt = 0x0001,
    Control = 0x0002,
    Shift = 0x0004,
    Windows = 0x0008,
}

public readonly record struct GlobalHotkeyBinding(
    GlobalHotkeyModifiers Modifiers,
    uint VirtualKey)
{
    public static GlobalHotkeyBinding Disabled { get; } = new(GlobalHotkeyModifiers.None, 0);

    public bool IsDisabled => this == Disabled;

    private const GlobalHotkeyModifiers SupportedModifiers = GlobalHotkeyModifiers.Alt
        | GlobalHotkeyModifiers.Control
        | GlobalHotkeyModifiers.Shift
        | GlobalHotkeyModifiers.Windows;

    public bool IsValid() => Modifiers != GlobalHotkeyModifiers.None
        && (Modifiers & ~SupportedModifiers) == 0
        && VirtualKey is >= 0x08 and <= 0xFE
        && !IsModifierKey(VirtualKey);

    public string ToDisplayText()
    {
        if (IsDisabled)
            return string.Empty;

        var parts = new List<string>(5);
        if (Modifiers.HasFlag(GlobalHotkeyModifiers.Control))
            parts.Add("Ctrl");
        if (Modifiers.HasFlag(GlobalHotkeyModifiers.Alt))
            parts.Add("Alt");
        if (Modifiers.HasFlag(GlobalHotkeyModifiers.Shift))
            parts.Add("Shift");
        if (Modifiers.HasFlag(GlobalHotkeyModifiers.Windows))
            parts.Add("Win");
        parts.Add(KeyDisplayName(VirtualKey));
        return string.Join(" + ", parts);
    }

    public static GlobalHotkeyBinding FromLegacy(GlobalHotkeyKey key) =>
        new(GlobalHotkeyModifiers.Control | GlobalHotkeyModifiers.Alt, (uint)('A' + (int)key));

    public static bool IsModifierKey(uint virtualKey) => virtualKey is
        0x10 or 0x11 or 0x12 or
        0x5B or 0x5C or
        0xA0 or 0xA1 or 0xA2 or 0xA3 or 0xA4 or 0xA5;

    public static string ModifierDisplayText(GlobalHotkeyModifiers modifiers)
    {
        var parts = new List<string>(4);
        if (modifiers.HasFlag(GlobalHotkeyModifiers.Control))
            parts.Add("Ctrl");
        if (modifiers.HasFlag(GlobalHotkeyModifiers.Alt))
            parts.Add("Alt");
        if (modifiers.HasFlag(GlobalHotkeyModifiers.Shift))
            parts.Add("Shift");
        if (modifiers.HasFlag(GlobalHotkeyModifiers.Windows))
            parts.Add("Win");
        return string.Join(" + ", parts);
    }

    internal static GlobalHotkeyKey LegacyKeyOrFallback(uint virtualKey, GlobalHotkeyKey fallback) =>
        virtualKey is >= 'A' and <= 'Z' ? (GlobalHotkeyKey)(virtualKey - 'A') : fallback;

    private static string KeyDisplayName(uint key) => key switch
    {
        >= 0x30 and <= 0x39 => ((char)key).ToString(),
        >= 0x41 and <= 0x5A => ((char)key).ToString(),
        >= 0x60 and <= 0x69 => $"Num {key - 0x60}",
        >= 0x70 and <= 0x87 => $"F{key - 0x6F}",
        0x08 => "Backspace",
        0x09 => "Tab",
        0x0D => "Enter",
        0x13 => "Pause",
        0x14 => "Caps Lock",
        0x1B => "Esc",
        0x20 => "Space",
        0x21 => "Page Up",
        0x22 => "Page Down",
        0x23 => "End",
        0x24 => "Home",
        0x25 => "Left",
        0x26 => "Up",
        0x27 => "Right",
        0x28 => "Down",
        0x2C => "Print Screen",
        0x2D => "Insert",
        0x2E => "Delete",
        0x5D => "Menu",
        0x6A => "Num *",
        0x6B => "Num +",
        0x6D => "Num -",
        0x6E => "Num .",
        0x6F => "Num /",
        0x90 => "Num Lock",
        0x91 => "Scroll Lock",
        0xAD => "Mute",
        0xAE => "Volume Down",
        0xAF => "Volume Up",
        0xBA => ";",
        0xBB => "+",
        0xBC => ",",
        0xBD => "-",
        0xBE => ".",
        0xBF => "/",
        0xC0 => "`",
        0xDB => "[",
        0xDC => "\\",
        0xDD => "]",
        0xDE => "'",
        _ => $"Key 0x{key:X2}",
    };
}

public sealed record GlobalHotkeySettings(
    GlobalHotkeyKey ToggleOverlay,
    GlobalHotkeyKey ToggleQuietMode,
    GlobalHotkeyKey Compose,
    GlobalHotkeyKey History)
{
    public GlobalHotkeyBinding? ToggleOverlayBinding { get; init; }
    public GlobalHotkeyBinding? ToggleQuietModeBinding { get; init; }
    public GlobalHotkeyBinding? ComposeBinding { get; init; }
    public GlobalHotkeyBinding? HistoryBinding { get; init; }

    public static GlobalHotkeySettings Default { get; } = WithLegacyBindings(new(
        GlobalHotkeyKey.H,
        GlobalHotkeyKey.M,
        GlobalHotkeyKey.I,
        GlobalHotkeyKey.R));

    public GlobalHotkeySettings Normalize()
    {
        if (!Enum.IsDefined(ToggleOverlay) || !Enum.IsDefined(ToggleQuietMode)
            || !Enum.IsDefined(Compose) || !Enum.IsDefined(History))
        {
            return Default;
        }

        GlobalHotkeySettings hydrated = this with
        {
            ToggleOverlayBinding = ValidOrLegacy(ToggleOverlayBinding, ToggleOverlay),
            ToggleQuietModeBinding = ValidOrLegacy(ToggleQuietModeBinding, ToggleQuietMode),
            ComposeBinding = ValidOrLegacy(ComposeBinding, Compose),
            HistoryBinding = ValidOrLegacy(HistoryBinding, History),
        };
        GlobalHotkeyBinding[] bindings =
            [.. Enum.GetValues<GlobalHotkeyAction>().Select(hydrated.BindingFor)];
        GlobalHotkeyBinding[] enabled = [.. bindings.Where(binding => !binding.IsDisabled)];
        return bindings.All(binding => binding.IsValid() || binding.IsDisabled)
            && enabled.Distinct().Count() == enabled.Length
            ? hydrated
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

    public GlobalHotkeyBinding BindingFor(GlobalHotkeyAction action) => action switch
    {
        GlobalHotkeyAction.ToggleOverlay => ToggleOverlayBinding ?? GlobalHotkeyBinding.FromLegacy(ToggleOverlay),
        GlobalHotkeyAction.ToggleQuietMode => ToggleQuietModeBinding ?? GlobalHotkeyBinding.FromLegacy(ToggleQuietMode),
        GlobalHotkeyAction.Compose => ComposeBinding ?? GlobalHotkeyBinding.FromLegacy(Compose),
        GlobalHotkeyAction.History => HistoryBinding ?? GlobalHotkeyBinding.FromLegacy(History),
        _ => throw new ArgumentOutOfRangeException(nameof(action)),
    };

    public GlobalHotkeySettings Assign(GlobalHotkeyAction action, GlobalHotkeyKey key) =>
        Enum.IsDefined(key) ? Assign(action, GlobalHotkeyBinding.FromLegacy(key)) : Normalize();

    public GlobalHotkeySettings Assign(GlobalHotkeyAction action, GlobalHotkeyBinding binding)
    {
        if (!binding.IsValid() && !binding.IsDisabled)
            return Normalize();

        GlobalHotkeySettings current = Normalize();
        GlobalHotkeyBinding previous = current.BindingFor(action);
        GlobalHotkeyAction? occupied = binding.IsDisabled ? null : Enum.GetValues<GlobalHotkeyAction>()
            .Cast<GlobalHotkeyAction?>()
            .FirstOrDefault(candidate => candidate != action && current.BindingFor(candidate!.Value) == binding);
        GlobalHotkeySettings assigned = current.Set(action, binding);
        return occupied is { } other ? assigned.Set(other, previous) : assigned;
    }

    private static GlobalHotkeyBinding ValidOrLegacy(
        GlobalHotkeyBinding? binding,
        GlobalHotkeyKey legacyKey) =>
        binding is { } value && (value.IsValid() || value.IsDisabled)
            ? value : GlobalHotkeyBinding.FromLegacy(legacyKey);

    private static GlobalHotkeySettings WithLegacyBindings(GlobalHotkeySettings settings) => settings with
    {
        ToggleOverlayBinding = GlobalHotkeyBinding.FromLegacy(settings.ToggleOverlay),
        ToggleQuietModeBinding = GlobalHotkeyBinding.FromLegacy(settings.ToggleQuietMode),
        ComposeBinding = GlobalHotkeyBinding.FromLegacy(settings.Compose),
        HistoryBinding = GlobalHotkeyBinding.FromLegacy(settings.History),
    };

    private GlobalHotkeySettings Set(GlobalHotkeyAction action, GlobalHotkeyBinding binding) => action switch
    {
        GlobalHotkeyAction.ToggleOverlay => this with
        {
            ToggleOverlay = GlobalHotkeyBinding.LegacyKeyOrFallback(binding.VirtualKey, ToggleOverlay),
            ToggleOverlayBinding = binding,
        },
        GlobalHotkeyAction.ToggleQuietMode => this with
        {
            ToggleQuietMode = GlobalHotkeyBinding.LegacyKeyOrFallback(binding.VirtualKey, ToggleQuietMode),
            ToggleQuietModeBinding = binding,
        },
        GlobalHotkeyAction.Compose => this with
        {
            Compose = GlobalHotkeyBinding.LegacyKeyOrFallback(binding.VirtualKey, Compose),
            ComposeBinding = binding,
        },
        GlobalHotkeyAction.History => this with
        {
            History = GlobalHotkeyBinding.LegacyKeyOrFallback(binding.VirtualKey, History),
            HistoryBinding = binding,
        },
        _ => throw new ArgumentOutOfRangeException(nameof(action)),
    };
}
