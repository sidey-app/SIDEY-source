using System.Text;
using System.Text.Json;
using Sidey.Core.Localization;

namespace Sidey.Infrastructure.Configuration;

public sealed record SupabaseRuntimeConfiguration(Uri Url, string PublishableKey)
{
    public const string ProductionHost = "whtejsviizgejauasqqt.supabase.co";
    public const string ProductionPublishableKey = "sb_publishable_kkASOI4rRTX8Drob21hkCw_VwUex63Y";

    public static SupabaseRuntimeConfiguration FromEnvironment()
    {
#if DEBUG
        return FromEnvironment(allowOverride: true);
#else
        return FromEnvironment(allowOverride: false);
#endif
    }

    internal static SupabaseRuntimeConfiguration FromEnvironment(bool allowOverride)
    {
        if (!allowOverride)
        {
            return Production();
        }

        string? url = Environment.GetEnvironmentVariable("SIDEY_SUPABASE_URL")?.Trim();
        string? key = Environment.GetEnvironmentVariable("SIDEY_SUPABASE_PUBLISHABLE_KEY")?.Trim();
        if (string.IsNullOrEmpty(url) && string.IsNullOrEmpty(key))
        {
            return Production();
        }

        if (!Uri.TryCreate(url, UriKind.Absolute, out Uri? parsed)
            || !IsAllowedBackend(parsed)
            || string.IsNullOrWhiteSpace(key)
            || LooksLikeSecretKey(key))
        {
            throw new InvalidOperationException(
                I18n.Get("configuration.backend.override_invalid"));
        }

        return new SupabaseRuntimeConfiguration(parsed, key);
    }

    private static SupabaseRuntimeConfiguration Production() => new(
        new Uri($"https://{ProductionHost}"),
        ProductionPublishableKey);

    internal static bool IsAllowedBackend(Uri url) =>
        url.Scheme == Uri.UriSchemeHttps
        || (url.Scheme == Uri.UriSchemeHttp && url.IsLoopback);

    internal static bool LooksLikeSecretKey(string value)
    {
        if (value.StartsWith("sb_secret_", StringComparison.OrdinalIgnoreCase)
            || value.StartsWith("service_role", StringComparison.OrdinalIgnoreCase))
        {
            return true;
        }

        string[] parts = value.Split('.');
        if (parts.Length != 3)
        {
            return false;
        }

        try
        {
            string encoded = parts[1].Replace('-', '+').Replace('_', '/');
            encoded = encoded.PadRight(encoded.Length + ((4 - (encoded.Length % 4)) % 4), '=');
            using var document = JsonDocument.Parse(Encoding.UTF8.GetString(Convert.FromBase64String(encoded)));
            return document.RootElement.TryGetProperty("role", out JsonElement role)
                && role.GetString() == "service_role";
        }
        catch (Exception exception) when (exception is FormatException or JsonException)
        {
            return false;
        }
    }
}
