using System;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using Microsoft.Win32;
using Sidey.Installer;

#if !SIDEY_LAUNCHER_FOREGROUND_TEST
public static class Program
{
    private const string LanguageEnvironmentVariable = "SIDEY_LANGUAGE";
    private const string InstallerRegistryPath = @"Software\SIDEY\Installer";

    [STAThread]
    public static int Main(string[] arguments)
    {
        string deploymentRoot = AppDomain.CurrentDomain.BaseDirectory;
        string hostPath = Path.Combine(deploymentRoot, "Runtime", "SIDEY.Host.exe");
        if (!File.Exists(hostPath))
        {
            MessageBox(
                IntPtr.Zero,
                Localize(deploymentRoot, "app.startup.runtime_missing", "SIDEY Runtime\\SIDEY.Host.exe was not found. Reinstall SIDEY."),
                Localize(deploymentRoot, "app.startup.error.title", "SIDEY Startup Error"),
                0x10);
            return 2;
        }

        try
        {
            string language = ResolveLanguage(ResolveRequestedLanguage());
            var start = new ProcessStartInfo
            {
                FileName = hostPath,
                // WinUI's PRI/XAML loader resolves app resources relative to the
                // real host directory, not the public launcher directory.
                WorkingDirectory = Path.GetDirectoryName(hostPath),
                UseShellExecute = false,
                Arguments = JoinArguments(arguments),
            };
            start.EnvironmentVariables[LanguageEnvironmentVariable] = language;
            Process process = Process.Start(start);
            if (process != null)
            {
                using (process)
                {
                    LauncherForegroundPermission.TryGrantToProcess(process.Id);
                }
            }
            return 0;
        }
        catch (Exception exception)
        {
            MessageBox(
                IntPtr.Zero,
                Localize(deploymentRoot, "app.startup.failed", "SIDEY could not start.")
                    + "\r\n\r\n" + exception.Message,
                Localize(deploymentRoot, "app.startup.error.title", "SIDEY Startup Error"),
                0x10);
            return 1;
        }
    }

    private static string Localize(string deploymentRoot, string key, string fallback)
    {
        try
        {
            string requested = ResolveRequestedLanguage();
            string language = ResolveLanguage(requested);
            string path = Path.Combine(deploymentRoot, "Langs", language + ".json");
            string json = File.ReadAllText(path, Encoding.UTF8);
            string localized;
            if (LauncherLocalization.TryGet(json, key, out localized))
            {
                return localized;
            }
        }
        catch
        {
            // The launcher must still report startup failures when catalogs are damaged.
        }

        return fallback;
    }

    private static string ResolveRequestedLanguage()
    {
        string explicitLanguage = Environment.GetEnvironmentVariable(LanguageEnvironmentVariable);
        if (!string.IsNullOrWhiteSpace(explicitLanguage))
        {
            return explicitLanguage;
        }

        try
        {
            using (RegistryKey machine = RegistryKey.OpenBaseKey(
                RegistryHive.LocalMachine,
                RegistryView.Registry64))
            using (RegistryKey installer = machine.OpenSubKey(InstallerRegistryPath, writable: false))
            {
                object savedValue = installer == null ? null : installer.GetValue("Language");
                int installerLanguage;
                if (int.TryParse(
                    Convert.ToString(savedValue, CultureInfo.InvariantCulture),
                    NumberStyles.Integer,
                    CultureInfo.InvariantCulture,
                    out installerLanguage))
                {
                    string appLanguage = InstallerLanguages.AppLanguage(installerLanguage);
                    if (!string.IsNullOrWhiteSpace(appLanguage))
                    {
                        return appLanguage;
                    }
                }
            }
        }
        catch
        {
            // A damaged or inaccessible installer key must not prevent launch.
        }

        return CultureInfo.CurrentUICulture.Name;
    }

    private static string ResolveLanguage(string requested)
    {
        if (requested.StartsWith("en", StringComparison.OrdinalIgnoreCase))
            return "en-US";
        if (requested.StartsWith("ja", StringComparison.OrdinalIgnoreCase))
            return "ja-JP";
        if (requested.StartsWith("zh-Hant", StringComparison.OrdinalIgnoreCase)
            || requested.StartsWith("zh-TW", StringComparison.OrdinalIgnoreCase)
            || requested.StartsWith("zh-HK", StringComparison.OrdinalIgnoreCase)
            || requested.StartsWith("zh-MO", StringComparison.OrdinalIgnoreCase))
            return "zh-TW";
        if (requested.StartsWith("zh", StringComparison.OrdinalIgnoreCase))
            return "zh-CN";
        if (requested.StartsWith("uk", StringComparison.OrdinalIgnoreCase))
            return "uk-UA";
        if (requested.StartsWith("ru", StringComparison.OrdinalIgnoreCase))
            return "ru-RU";
        if (requested.StartsWith("it", StringComparison.OrdinalIgnoreCase))
            return "it-IT";
        if (requested.StartsWith("pt-BR", StringComparison.OrdinalIgnoreCase))
            return "pt-BR";
        if (requested.StartsWith("pt", StringComparison.OrdinalIgnoreCase))
            return "pt-PT";
        if (requested.StartsWith("es", StringComparison.OrdinalIgnoreCase))
            return "es-ES";
        if (requested.StartsWith("cs", StringComparison.OrdinalIgnoreCase))
            return "cs-CZ";
        if (requested.StartsWith("tr", StringComparison.OrdinalIgnoreCase))
            return "tr-TR";
        if (requested.StartsWith("ro", StringComparison.OrdinalIgnoreCase))
            return "ro-RO";
        if (requested.StartsWith("bg", StringComparison.OrdinalIgnoreCase))
            return "bg-BG";
        if (requested.StartsWith("sr-Latn", StringComparison.OrdinalIgnoreCase))
            return "sr-Latn-RS";
        if (requested.StartsWith("sr", StringComparison.OrdinalIgnoreCase))
            return "sr-Cyrl-RS";
        if (requested.StartsWith("pl", StringComparison.OrdinalIgnoreCase))
            return "pl-PL";
        if (requested.StartsWith("nl-BE", StringComparison.OrdinalIgnoreCase))
            return "nl-BE";
        if (requested.StartsWith("nl", StringComparison.OrdinalIgnoreCase))
            return "nl-NL";
        if (requested.StartsWith("fr", StringComparison.OrdinalIgnoreCase))
            return "fr-FR";
        if (requested.StartsWith("he", StringComparison.OrdinalIgnoreCase)
            || requested.StartsWith("iw", StringComparison.OrdinalIgnoreCase))
            return "he-IL";
        if (requested.StartsWith("de", StringComparison.OrdinalIgnoreCase))
            return "de-DE";

        return "ko-KR";
    }

    private static string JoinArguments(string[] arguments)
    {
        var commandLine = new StringBuilder();
        foreach (string argument in arguments)
        {
            if (commandLine.Length > 0)
            {
                commandLine.Append(' ');
            }

            commandLine.Append(QuoteArgument(argument));
        }
        return commandLine.ToString();
    }

    private static string QuoteArgument(string argument)
    {
        if (argument.Length > 0
            && argument.IndexOfAny(new[] { ' ', '\t', '\n', '\v', '"' }) < 0)
        {
            return argument;
        }

        var quoted = new StringBuilder();
        quoted.Append('"');
        int backslashes = 0;
        foreach (char character in argument)
        {
            if (character == '\\')
            {
                backslashes++;
                continue;
            }
            if (character == '"')
            {
                quoted.Append('\\', (backslashes * 2) + 1);
                quoted.Append('"');
                backslashes = 0;
                continue;
            }

            quoted.Append('\\', backslashes);
            backslashes = 0;
            quoted.Append(character);
        }
        quoted.Append('\\', backslashes * 2);
        quoted.Append('"');
        return quoted.ToString();
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int MessageBox(
        IntPtr window,
        string text,
        string caption,
        uint type);
}
#endif

#nullable enable
internal static class LauncherLocalization
{
    internal static bool TryGet(string json, string dottedKey, out string? value)
    {
        value = null;
        if (string.IsNullOrWhiteSpace(json) || string.IsNullOrWhiteSpace(dottedKey))
        {
            return false;
        }

        string[] segments = dottedKey.Split('.');
        int index = 0;
        return TryReadObjectPath(json, ref index, segments, 0, out value);
    }

    private static bool TryReadObjectPath(
        string json,
        ref int index,
        string[] segments,
        int segmentIndex,
        out string? value)
    {
        value = null;
        SkipWhitespace(json, ref index);
        if (index >= json.Length || json[index] != '{')
        {
            return false;
        }
        index++;

        while (index < json.Length)
        {
            SkipWhitespace(json, ref index);
            if (index < json.Length && json[index] == '}')
            {
                index++;
                return false;
            }

            string? propertyName;
            if (!TryReadString(json, ref index, out propertyName))
            {
                return false;
            }
            SkipWhitespace(json, ref index);
            if (index >= json.Length || json[index] != ':')
            {
                return false;
            }
            index++;

            if (string.Equals(propertyName, segments[segmentIndex], StringComparison.Ordinal))
            {
                if (segmentIndex == segments.Length - 1)
                {
                    SkipWhitespace(json, ref index);
                    return TryReadString(json, ref index, out value);
                }
                return TryReadObjectPath(json, ref index, segments, segmentIndex + 1, out value);
            }

            if (!TrySkipValue(json, ref index))
            {
                return false;
            }
            SkipWhitespace(json, ref index);
            if (index < json.Length && json[index] == ',')
            {
                index++;
                continue;
            }
            if (index < json.Length && json[index] == '}')
            {
                index++;
                return false;
            }
            return false;
        }

        return false;
    }

    private static bool TryReadString(string json, ref int index, out string? value)
    {
        value = null;
        SkipWhitespace(json, ref index);
        if (index >= json.Length || json[index] != '"')
        {
            return false;
        }

        int start = ++index;
        bool escaped = false;
        while (index < json.Length)
        {
            char character = json[index++];
            if (escaped)
            {
                escaped = false;
                continue;
            }
            if (character == '\\')
            {
                escaped = true;
                continue;
            }
            if (character == '"')
            {
                string encoded = json.Substring(start, index - start - 1);
                value = Regex.Unescape(encoded.Replace("\\/", "/"));
                return true;
            }
        }
        return false;
    }

    private static bool TrySkipValue(string json, ref int index)
    {
        SkipWhitespace(json, ref index);
        if (index >= json.Length)
        {
            return false;
        }
        if (json[index] == '"')
        {
            string? ignored;
            return TryReadString(json, ref index, out ignored);
        }
        if (json[index] != '{' && json[index] != '[')
        {
            while (index < json.Length && json[index] != ',' && json[index] != '}' && json[index] != ']')
            {
                index++;
            }
            return true;
        }

        char opening = json[index];
        char closing = opening == '{' ? '}' : ']';
        int depth = 0;
        while (index < json.Length)
        {
            if (json[index] == '"')
            {
                string? ignored;
                if (!TryReadString(json, ref index, out ignored))
                {
                    return false;
                }
                continue;
            }
            if (json[index] == opening)
            {
                depth++;
            }
            else if (json[index] == closing && --depth == 0)
            {
                index++;
                return true;
            }
            index++;
        }
        return false;
    }

    private static void SkipWhitespace(string json, ref int index)
    {
        while (index < json.Length && char.IsWhiteSpace(json[index]))
        {
            index++;
        }
    }
}
#nullable restore

internal interface ILauncherForegroundPermissionApi
{
    public bool AllowSetForegroundWindow(uint processId);
}

internal static class LauncherForegroundPermission
{
    internal static void TryGrantToProcess(int processId) =>
        TryGrantToProcess(processId, new NativeLauncherForegroundPermissionApi());

    internal static void TryGrantToProcess(
        int processId,
        ILauncherForegroundPermissionApi api)
    {
        if (processId <= 0)
        {
            return;
        }

        try
        {
            _ = api.AllowSetForegroundWindow((uint)processId);
        }
        catch (Exception)
        {
            // Foreground permission is best effort; the host must still be allowed to start.
        }
    }

    private sealed class NativeLauncherForegroundPermissionApi : ILauncherForegroundPermissionApi
    {
        public bool AllowSetForegroundWindow(uint processId) =>
            NativeMethods.AllowSetForegroundWindow(processId);
    }

    private static class NativeMethods
    {
        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool AllowSetForegroundWindow(uint processId);
    }
}
