using Sidey.Core.Storage;

namespace Sidey.Platform.Windows.Deployment;

public sealed class WindowsPostInstallLaunchTracker
{
    private readonly string _path;

    public WindowsPostInstallLaunchTracker(string? path = null)
    {
        _path = path ?? Path.Combine(
            SideyStoragePaths.LocalApplicationDataRoot(),
            "SIDEY",
            "pending-postinstall-about.txt");
    }

    public bool IsPending() => File.Exists(_path);

    public bool TryMarkShown()
    {
        try
        {
            File.Delete(_path);
            return true;
        }
        catch (IOException)
        {
            return false;
        }
        catch (UnauthorizedAccessException)
        {
            return false;
        }
    }
}
