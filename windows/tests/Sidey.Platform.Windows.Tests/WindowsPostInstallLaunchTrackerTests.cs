using Sidey.Platform.Windows.Deployment;

namespace Sidey.Platform.Windows.Tests;

public sealed class WindowsPostInstallLaunchTrackerTests : IDisposable
{
    private readonly string _directory = Path.Combine(
        Path.GetTempPath(), $"sidey-postinstall-launch-{Guid.NewGuid():N}");

    [Fact]
    public void CompletedInstallationIsOfferedUntilAboutIsShown()
    {
        Directory.CreateDirectory(_directory);
        File.WriteAllText(StatePath(), "install-id");
        var tracker = new WindowsPostInstallLaunchTracker(StatePath());

        Assert.True(tracker.IsPending());
        Assert.True(tracker.TryMarkShown());
        Assert.False(tracker.IsPending());
    }

    [Fact]
    public void OrdinaryLaunchWithoutInstallerMarkerDoesNotRequestAbout()
    {
        var tracker = new WindowsPostInstallLaunchTracker(StatePath());

        Assert.False(tracker.IsPending());
    }

    public void Dispose()
    {
        if (Directory.Exists(_directory))
            Directory.Delete(_directory, recursive: true);
    }

    private string StatePath() => Path.Combine(_directory, "pending-postinstall-about.txt");
}
