namespace Sidey.Presentation.Services;

public sealed record MonitorOption(string Identifier, string Name, bool IsPrimary);

public sealed record ValidationMetricsSnapshot(
    double ElapsedSeconds,
    int SampleCount,
    double MaximumFrameMilliseconds,
    long CurrentWorkingSetBytes,
    long PeakWorkingSetBytes,
    uint MaximumGdiHandles,
    uint MaximumUserHandles);

public sealed record AvailableUpdate(
    string Version,
    Uri? InstallerUri = null,
    string? Sha256 = null,
    Uri? ReleaseNotesUri = null,
    string? UpdateVersion = null,
    string? UpdateTag = null);

public interface IUpdateService
{
    public string CurrentVersion { get; }

    public string CurrentUpdateVersion { get; }

    public DateTimeOffset? LastCheckedAt { get; }

    public Uri CurrentReleaseNotesUri { get; }

    public Task<AvailableUpdate?> CheckAsync(CancellationToken cancellationToken = default);

    public Task DownloadAndLaunchInstallerAsync(
        AvailableUpdate update,
        CancellationToken cancellationToken = default,
        IProgress<int>? progress = null);

    public Task OpenReleaseNotesAsync(Uri releaseNotesUri);
}
