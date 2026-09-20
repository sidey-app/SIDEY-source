using System.Diagnostics;
using System.Net;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;
using Sidey.Core.Localization;

namespace Sidey.Platform.Windows.Deployment;

public sealed record WindowsUpdateManifest(
    string Channel,
    string Version,
    string Tag,
    Uri InstallerUri,
    string Sha256);

public sealed partial class WindowsUpdateService
{
    public const string CurrentVersion = "2.0.0";
    public static readonly Uri ManifestUri = new(
        "https://sidey-app.github.io/SIDEY/windows-latest.json");
    private readonly HttpClient _httpClient;
    private readonly string _updateCacheDirectory;

    public WindowsUpdateService(
        HttpClient? httpClient = null,
        string? currentVersion = null,
        string? updateCacheDirectory = null)
    {
        _httpClient = httpClient ?? new HttpClient();
        _updateCacheDirectory = Path.GetFullPath(updateCacheDirectory
            ?? Path.Combine(Path.GetTempPath(), "SIDEY", "Updates"));
        EffectiveCurrentVersion = string.IsNullOrWhiteSpace(currentVersion)
            ? CurrentVersion
            : currentVersion;
        _ = ParsedVersion.Parse(EffectiveCurrentVersion);
    }

    public string EffectiveCurrentVersion { get; }

    // Only remove updater-owned files after the app has started successfully.
    // Locked installers are left for the next startup; never traverse links or
    // recursively remove a directory that might contain unrelated files.
    public int CleanupInstalledUpdates()
    {
        int deletedFiles = 0;
        try
        {
            if (!Directory.Exists(_updateCacheDirectory)
                || HasReparsePointAncestor(new DirectoryInfo(_updateCacheDirectory)))
            {
                return 0;
            }

            foreach (string directory in Directory.GetDirectories(_updateCacheDirectory))
            {
                try
                {
                    if ((File.GetAttributes(directory) & FileAttributes.ReparsePoint) != 0)
                    {
                        continue;
                    }

                    string version = Path.GetFileName(directory);
                    if (IsNewerVersion(version, EffectiveCurrentVersion))
                    {
                        continue;
                    }

                    string installerName = $"SIDEY-Windows-x64-v{version}";
                    foreach (string suffix in new[] { "-Setup.exe", "-Setup.exe.download", ".msi", ".msi.download" })
                    {
                        string file = Path.Combine(directory, installerName + suffix);
                        try
                        {
                            if (File.Exists(file)
                                && (File.GetAttributes(file) & FileAttributes.ReparsePoint) == 0)
                            {
                                File.Delete(file);
                                deletedFiles++;
                            }
                        }
                        catch (IOException) { }
                        catch (UnauthorizedAccessException) { }
                    }

                    // Non-recursive deletion succeeds only when the folder is empty.
                    Directory.Delete(directory, recursive: false);
                }
                catch (InvalidDataException) { }
                catch (IOException) { }
                catch (UnauthorizedAccessException) { }
                catch (FormatException) { }
                catch (OverflowException) { }
            }
        }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }

        return deletedFiles;
    }

    private static bool HasReparsePointAncestor(DirectoryInfo directory)
    {
        for (DirectoryInfo? current = directory; current is not null; current = current.Parent)
        {
            if ((current.Attributes & FileAttributes.ReparsePoint) != 0)
            {
                return true;
            }
        }

        return false;
    }

    public async Task<WindowsUpdateManifest?> CheckAsync(
        CancellationToken cancellationToken = default)
    {
        ManifestDto? manifest;
        try
        {
            manifest = await _httpClient.GetFromJsonAsync<ManifestDto>(
                ManifestUri,
                cancellationToken).ConfigureAwait(false);
        }
        catch (HttpRequestException exception) when (exception.StatusCode == HttpStatusCode.NotFound)
        {
            throw new InvalidOperationException(
                I18n.Get("update.notPublished"),
                exception);
        }
        if (manifest is null
            || manifest.Channel is not ("alpha" or "production")
            || string.IsNullOrWhiteSpace(manifest.Version)
            || manifest.Tag != $"windows-v{manifest.Version}")
        {
            throw new InvalidDataException(I18n.Get("update.invalidManifest"));
        }

        if (!IsNewerVersion(manifest.Version, EffectiveCurrentVersion))
        {
            return null;
        }

        var expectedInstallerUri = new Uri(
            $"https://github.com/sidey-app/SIDEY/releases/download/{manifest.Tag}/" +
            $"SIDEY-Windows-x64-v{manifest.Version}-Setup.exe");
        if (!Uri.TryCreate(manifest.InstallerUrl, UriKind.Absolute, out Uri? installerUri)
            || installerUri != expectedInstallerUri
            || string.IsNullOrWhiteSpace(manifest.Sha256)
            || !Sha256Pattern().IsMatch(manifest.Sha256))
        {
            throw new InvalidDataException(
                I18n.Get("update.invalidInstaller"));
        }

        return new WindowsUpdateManifest(
            manifest.Channel,
            manifest.Version,
            manifest.Tag,
            installerUri,
            manifest.Sha256.ToLowerInvariant());
    }

    public async Task<string> DownloadInstallerAsync(
        WindowsUpdateManifest manifest,
        CancellationToken cancellationToken = default,
        IProgress<int>? progress = null)
    {
        ArgumentNullException.ThrowIfNull(manifest);
        string updateDirectory = Path.Combine(
            _updateCacheDirectory,
            manifest.Version);
        Directory.CreateDirectory(updateDirectory);
        string installerPath = Path.Combine(
            updateDirectory,
            Path.GetFileName(manifest.InstallerUri.LocalPath));
        string partialPath = $"{installerPath}.download";

        try
        {
            using HttpResponseMessage response = await _httpClient.GetAsync(
                manifest.InstallerUri,
                HttpCompletionOption.ResponseHeadersRead,
                cancellationToken).ConfigureAwait(false);
            response.EnsureSuccessStatusCode();
            await using (Stream source = await response.Content.ReadAsStreamAsync(
                cancellationToken).ConfigureAwait(false))
            await using (var destination = new FileStream(
                partialPath,
                FileMode.Create,
                FileAccess.Write,
                FileShare.None,
                bufferSize: 81920,
                useAsync: true))
            {
                long? totalBytes = response.Content.Headers.ContentLength;
                long downloadedBytes = 0;
                int lastReportedPercentage = -1;
                byte[] buffer = new byte[81920];

                if (totalBytes is > 0)
                {
                    progress?.Report(0);
                    lastReportedPercentage = 0;
                }

                int bytesRead;
                while ((bytesRead = await source.ReadAsync(
                    buffer,
                    cancellationToken).ConfigureAwait(false)) > 0)
                {
                    await destination.WriteAsync(
                        buffer.AsMemory(0, bytesRead),
                        cancellationToken).ConfigureAwait(false);
                    downloadedBytes += bytesRead;

                    if (totalBytes is > 0)
                    {
                        int percentage = (int)Math.Clamp(
                            downloadedBytes * 100d / totalBytes.Value,
                            0d,
                            100d);
                        if (percentage != lastReportedPercentage)
                        {
                            progress?.Report(percentage);
                            lastReportedPercentage = percentage;
                        }
                    }
                }
            }

            string actualHash;
            await using (FileStream downloaded = File.OpenRead(partialPath))
            {
                byte[] digest = await SHA256.HashDataAsync(downloaded, cancellationToken)
                    .ConfigureAwait(false);
                actualHash = Convert.ToHexStringLower(digest);
            }

            if (!StringComparer.OrdinalIgnoreCase.Equals(actualHash, manifest.Sha256))
            {
                throw new InvalidDataException(
                    I18n.Get("update.hashMismatch"));
            }

            File.Move(partialPath, installerPath, overwrite: true);
            return installerPath;
        }
        catch
        {
            File.Delete(partialPath);
            throw;
        }
    }

    public static void LaunchInstaller(string installerPath)
    {
        if (!OperatingSystem.IsWindows())
        {
            throw new PlatformNotSupportedException("The Windows shell is required.");
        }

        Process.Start(new ProcessStartInfo(installerPath) { UseShellExecute = true });
    }

    public static bool IsNewerVersion(string candidate, string current)
    {
        var candidateVersion = ParsedVersion.Parse(candidate);
        var currentVersion = ParsedVersion.Parse(current);
        return candidateVersion.CompareTo(currentVersion) > 0;
    }

    private sealed record ManifestDto(
        [property: JsonPropertyName("channel")] string Channel,
        [property: JsonPropertyName("version")] string Version,
        [property: JsonPropertyName("tag")] string Tag,
        [property: JsonPropertyName("installer_url")] string? InstallerUrl,
        [property: JsonPropertyName("sha256")] string? Sha256);

    [GeneratedRegex("^[0-9a-fA-F]{64}$", RegexOptions.CultureInvariant)]
    private static partial Regex Sha256Pattern();

    private sealed partial record ParsedVersion(
        int Major,
        int Minor,
        int Patch,
        IReadOnlyList<string> Prerelease) : IComparable<ParsedVersion>
    {
        public static ParsedVersion Parse(string value)
        {
            Match match = VersionPattern().Match(value);
            if (!match.Success)
            {
                throw new InvalidDataException($"SIDEY Windows version is not valid SemVer: {value}");
            }

            string[] prerelease = match.Groups["pre"].Success
                ? match.Groups["pre"].Value.Split('.', StringSplitOptions.RemoveEmptyEntries)
                : [];
            return new ParsedVersion(
                int.Parse(match.Groups["major"].Value, System.Globalization.CultureInfo.InvariantCulture),
                int.Parse(match.Groups["minor"].Value, System.Globalization.CultureInfo.InvariantCulture),
                int.Parse(match.Groups["patch"].Value, System.Globalization.CultureInfo.InvariantCulture),
                prerelease);
        }

        public int CompareTo(ParsedVersion? other)
        {
            if (other is null)
            {
                return 1;
            }

            int core = Major.CompareTo(other.Major);
            if (core == 0)
                core = Minor.CompareTo(other.Minor);
            if (core == 0)
                core = Patch.CompareTo(other.Patch);
            if (core != 0)
            {
                return core;
            }

            if (Prerelease.Count == 0 || other.Prerelease.Count == 0)
            {
                return Prerelease.Count == other.Prerelease.Count
                    ? 0
                    : Prerelease.Count == 0 ? 1 : -1;
            }

            for (int index = 0; index < Math.Min(Prerelease.Count, other.Prerelease.Count); index++)
            {
                bool candidateNumeric = int.TryParse(
                    Prerelease[index],
                    System.Globalization.NumberStyles.None,
                    System.Globalization.CultureInfo.InvariantCulture,
                    out int candidateNumber);
                bool currentNumeric = int.TryParse(
                    other.Prerelease[index],
                    System.Globalization.NumberStyles.None,
                    System.Globalization.CultureInfo.InvariantCulture,
                    out int currentNumber);
                int result;
                if (candidateNumeric && currentNumeric)
                {
                    result = candidateNumber.CompareTo(currentNumber);
                }
                else if (candidateNumeric != currentNumeric)
                {
                    result = candidateNumeric ? -1 : 1;
                }
                else
                {
                    result = StringComparer.Ordinal.Compare(Prerelease[index], other.Prerelease[index]);
                }

                if (result != 0)
                {
                    return result;
                }
            }

            return Prerelease.Count.CompareTo(other.Prerelease.Count);
        }

        [GeneratedRegex(
            @"^(?<major>0|[1-9]\d*)\.(?<minor>0|[1-9]\d*)\.(?<patch>0|[1-9]\d*)(?:-(?<pre>[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$",
            RegexOptions.CultureInvariant)]
        private static partial Regex VersionPattern();
    }
}
