using System.Globalization;
using System.Text.Json;

namespace Sidey.Core.Localization;

/// <summary>
/// Loads SIDEY's JSON language catalogs and resolves dotted i18n keys.
/// </summary>
public static class I18n
{
    public const string DefaultLanguage = "ko-KR";

    public static IReadOnlyList<string> SupportedLanguages { get; } = Array.AsReadOnly(
        [
            DefaultLanguage, "en-US", "ja-JP", "zh-CN", "zh-TW", "uk-UA", "ru-RU",
            "it-IT", "pt-PT", "es-ES", "cs-CZ", "tr-TR", "ro-RO", "bg-BG", "pt-BR",
            "sr-Cyrl-RS", "pl-PL", "sr-Latn-RS", "nl-BE", "fr-FR", "nl-NL", "he-IL",
            "de-DE",
        ]);

    private static readonly Lock s_syncRoot = new();
    private static IReadOnlyDictionary<string, string>? s_strings;
    private static string? s_languageOverride;
    private static string? s_catalogRootOverride;

    public static string Language => ResolveLanguage();
    public static CultureInfo Culture => CultureInfo.GetCultureInfo(Language);
    public static bool IsRightToLeft => Culture.TextInfo.IsRightToLeft;

    public static string Get(string key)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(key);

        IReadOnlyDictionary<string, string> catalog = GetCatalog();
        return catalog.TryGetValue(key, out string? value) ? value : key;
    }

    public static string Format(string key, params object?[] args)
    {
        return string.Format(Culture, Get(key), args);
    }

    public static void SetLanguage(string? language)
    {
        lock (s_syncRoot)
        {
            s_languageOverride = string.IsNullOrWhiteSpace(language) ? null : language;
            s_strings = null;
        }
    }

    public static void SetCatalogRoot(string? catalogRoot)
    {
        lock (s_syncRoot)
        {
            s_catalogRootOverride = string.IsNullOrWhiteSpace(catalogRoot)
                ? null
                : Path.GetFullPath(catalogRoot);
            s_strings = null;
        }
    }

    public static bool IsSupportedLanguage(string? language)
    {
        return SupportedLanguages.Contains(language, StringComparer.OrdinalIgnoreCase);
    }

    public static string NormalizeLanguage(string? requested)
    {
        if (string.IsNullOrWhiteSpace(requested))
        {
            return DefaultLanguage;
        }

        if (requested.StartsWith("ko", StringComparison.OrdinalIgnoreCase))
        {
            return DefaultLanguage;
        }
        if (requested.StartsWith("en", StringComparison.OrdinalIgnoreCase))
        {
            return "en-US";
        }
        if (requested.StartsWith("ja", StringComparison.OrdinalIgnoreCase))
        {
            return "ja-JP";
        }
        if (requested.StartsWith("zh-Hant", StringComparison.OrdinalIgnoreCase)
            || requested.StartsWith("zh-TW", StringComparison.OrdinalIgnoreCase)
            || requested.StartsWith("zh-HK", StringComparison.OrdinalIgnoreCase)
            || requested.StartsWith("zh-MO", StringComparison.OrdinalIgnoreCase))
        {
            return "zh-TW";
        }
        if (requested.StartsWith("zh", StringComparison.OrdinalIgnoreCase))
        {
            return "zh-CN";
        }
        if (requested.StartsWith("uk", StringComparison.OrdinalIgnoreCase))
        {
            return "uk-UA";
        }
        if (requested.StartsWith("ru", StringComparison.OrdinalIgnoreCase))
        {
            return "ru-RU";
        }
        if (requested.StartsWith("it", StringComparison.OrdinalIgnoreCase))
        {
            return "it-IT";
        }
        if (requested.StartsWith("pt-BR", StringComparison.OrdinalIgnoreCase))
        {
            return "pt-BR";
        }
        if (requested.StartsWith("pt", StringComparison.OrdinalIgnoreCase))
        {
            return "pt-PT";
        }
        if (requested.StartsWith("es", StringComparison.OrdinalIgnoreCase))
        {
            return "es-ES";
        }
        if (requested.StartsWith("cs", StringComparison.OrdinalIgnoreCase))
        {
            return "cs-CZ";
        }
        if (requested.StartsWith("tr", StringComparison.OrdinalIgnoreCase))
        {
            return "tr-TR";
        }
        if (requested.StartsWith("ro", StringComparison.OrdinalIgnoreCase))
        {
            return "ro-RO";
        }
        if (requested.StartsWith("bg", StringComparison.OrdinalIgnoreCase))
        {
            return "bg-BG";
        }
        if (requested.StartsWith("sr-Latn", StringComparison.OrdinalIgnoreCase))
        {
            return "sr-Latn-RS";
        }
        if (requested.StartsWith("sr", StringComparison.OrdinalIgnoreCase))
        {
            return "sr-Cyrl-RS";
        }
        if (requested.StartsWith("pl", StringComparison.OrdinalIgnoreCase))
        {
            return "pl-PL";
        }
        if (requested.StartsWith("nl-BE", StringComparison.OrdinalIgnoreCase))
        {
            return "nl-BE";
        }
        if (requested.StartsWith("nl", StringComparison.OrdinalIgnoreCase))
        {
            return "nl-NL";
        }
        if (requested.StartsWith("fr", StringComparison.OrdinalIgnoreCase))
        {
            return "fr-FR";
        }
        if (requested.StartsWith("he", StringComparison.OrdinalIgnoreCase)
            || requested.StartsWith("iw", StringComparison.OrdinalIgnoreCase))
        {
            return "he-IL";
        }
        if (requested.StartsWith("de", StringComparison.OrdinalIgnoreCase))
        {
            return "de-DE";
        }

        return DefaultLanguage;
    }

    private static IReadOnlyDictionary<string, string> GetCatalog()
    {
        lock (s_syncRoot)
        {
            return s_strings ??= LoadCatalog();
        }
    }

    private static IReadOnlyDictionary<string, string> LoadCatalog()
    {
        var catalog = new Dictionary<string, string>(StringComparer.Ordinal);
        string root = s_catalogRootOverride ?? FindCatalogRoot();

        LoadFile(Path.Combine(root, $"{DefaultLanguage}.json"), catalog);

        string language = ResolveLanguage();
        if (!string.Equals(language, DefaultLanguage, StringComparison.OrdinalIgnoreCase))
        {
            LoadFile(Path.Combine(root, $"{language}.json"), catalog);
        }

        string? parent = Directory.GetParent(root)?.FullName;
        if (parent is not null)
        {
            string internalRoot = Path.Combine(parent, "InternalLangs");
            LoadFile(Path.Combine(internalRoot, $"{DefaultLanguage}.json"), catalog);
            if (!string.Equals(language, DefaultLanguage, StringComparison.OrdinalIgnoreCase))
            {
                LoadFile(Path.Combine(internalRoot, $"{language}.json"), catalog);
            }
        }

        return catalog;
    }

    private static string ResolveLanguage()
    {
        string requested = s_languageOverride
            ?? Environment.GetEnvironmentVariable("SIDEY_LANGUAGE")
            ?? CultureInfo.CurrentUICulture.Name;

        return NormalizeLanguage(requested);
    }

    private static string FindCatalogRoot()
    {
        string baseDirectory = Path.GetFullPath(AppContext.BaseDirectory);
        string local = Path.Combine(baseDirectory, "Langs");
        if (Directory.Exists(local))
        {
            return local;
        }

        DirectoryInfo? directory = Directory.GetParent(baseDirectory.TrimEnd(Path.DirectorySeparatorChar));
        if (directory is not null)
        {
            string besideRuntime = Path.Combine(directory.FullName, "Langs");
            if (Directory.Exists(besideRuntime))
            {
                return besideRuntime;
            }
        }

        return local;
    }

    private static void LoadFile(string path, IDictionary<string, string> target)
    {
        if (!File.Exists(path))
        {
            return;
        }

        using var document = JsonDocument.Parse(
            File.ReadAllText(path),
            new JsonDocumentOptions { AllowTrailingCommas = true, CommentHandling = JsonCommentHandling.Skip });
        Flatten(document.RootElement, null, target);
    }

    private static void Flatten(JsonElement element, string? prefix, IDictionary<string, string> target)
    {
        foreach (JsonProperty property in element.EnumerateObject())
        {
            string key = string.IsNullOrEmpty(prefix) ? property.Name : $"{prefix}.{property.Name}";
            if (property.Value.ValueKind == JsonValueKind.Object)
            {
                Flatten(property.Value, key, target);
            }
            else if (property.Value.ValueKind == JsonValueKind.String)
            {
                target[key] = property.Value.GetString() ?? string.Empty;
            }
        }
    }
}
