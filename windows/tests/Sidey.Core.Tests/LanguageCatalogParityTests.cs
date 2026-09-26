using System.Text.Json;
using System.Text.RegularExpressions;
using Sidey.Core.Localization;

namespace Sidey.Core.Tests;

public sealed class LanguageCatalogParityTests
{
    public static IEnumerable<object[]> TranslatedLanguages =>
        I18n.SupportedLanguages
            .Where(language => language != I18n.DefaultLanguage)
            .Select(language => new object[] { language });

    [Theory]
    [MemberData(nameof(TranslatedLanguages))]
    public void EveryLanguageHasAllKeysAndPreservesFormatArguments(string language)
    {
        AssertCatalogParity("Langs", language);
    }

    [Theory]
    [MemberData(nameof(TranslatedLanguages))]
    public void EveryInternalLanguageHasAllKeysAndPreservesFormatArguments(string language)
    {
        AssertCatalogParity("InternalLangs", language);
    }

    private static void AssertCatalogParity(string directory, string language)
    {
        Dictionary<string, string> korean = Read(directory, "ko-KR");
        Dictionary<string, string> translated = Read(directory, language);
        Assert.Equal(korean.Keys.Order(), translated.Keys.Order());
        foreach ((string? key, string? value) in korean)
        {
            Assert.False(string.IsNullOrWhiteSpace(translated[key]), key);
            Assert.DoesNotMatch("[가-힣]", translated[key]);
            Assert.Equal(Placeholders(value), Placeholders(translated[key]));
        }
    }

    private static string[] Placeholders(string value) =>
        [.. Regex.Matches(value, @"\{\d+(?::[^}]+)?\}").Select(match => match.Value).Order()];

    private static Dictionary<string, string> Read(string directory, string language)
    {
        using var document = JsonDocument.Parse(File.ReadAllText(
            Path.Combine(AppContext.BaseDirectory, directory, language + ".json")));
        var result = new Dictionary<string, string>();
        Flatten(document.RootElement, "", result);
        return result;
    }

    private static void Flatten(JsonElement element, string prefix, Dictionary<string, string> result)
    {
        foreach (JsonProperty property in element.EnumerateObject())
        {
            string key = string.IsNullOrEmpty(prefix) ? property.Name : prefix + "." + property.Name;
            if (property.Value.ValueKind == JsonValueKind.Object)
                Flatten(property.Value, key, result);
            else
                result.Add(key, property.Value.GetString()!);
        }
    }
}
