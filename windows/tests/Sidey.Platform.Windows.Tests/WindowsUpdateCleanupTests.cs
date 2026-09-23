using Sidey.Platform.Windows;

namespace Sidey.Platform.Windows.Tests;

public sealed class WindowsUpdateCleanupTests : IDisposable
{
    private readonly string _cache = Directory.CreateTempSubdirectory("SIDEY-update-cleanup-").FullName;

    [Fact]
    public void RemovesInstalledVersionsButPreservesNewerUpdatesAndUnrelatedFiles()
    {
        string oldInstaller = CreateFile("1.0.9", "SIDEY-Windows-x64-v1.0.9-Setup.exe");
        string currentInstaller = CreateFile("1.0.10", "SIDEY-Windows-x64-v1.0.10-Setup.exe");
        string partial = CreateFile("1.0.10", "SIDEY-Windows-x64-v1.0.10-Setup.exe.download");
        string legacyInstaller = CreateFile("1.0.5", "SIDEY-Windows-x64-v1.0.5.msi");
        string prerelease = CreateFile("1.0.10-alpha.1", "SIDEY-Windows-x64-v1.0.10-alpha.1-Setup.exe");
        string futureInstaller = CreateFile("1.0.11", "SIDEY-Windows-x64-v1.0.11-Setup.exe");
        string futurePartial = CreateFile("1.0.11", "SIDEY-Windows-x64-v1.0.11-Setup.exe.download");
        string unrelated = CreateFile("1.0.10", "notes.txt");
        string nested = CreateFile("1.0.10/nested", "keep.txt");
        string invalidVersion = CreateFile("not-a-version", "SIDEY-Windows-x64-vnot-a-version-Setup.exe");
        string oversizedVersion = CreateFile("999999999999999999.0.0", "keep.txt");
        var service = new WindowsUpdateService(
            currentProductVersion: "1.0.10",
            currentUpdateVersion: "1.0.10",
            updateCacheDirectory: _cache);

        Assert.Equal(5, service.CleanupInstalledUpdates());

        foreach (string file in new[] { oldInstaller, currentInstaller, partial, legacyInstaller, prerelease })
        {
            Assert.False(File.Exists(file));
        }
        foreach (string file in new[] { futureInstaller, futurePartial, unrelated, nested, invalidVersion, oversizedVersion })
        {
            Assert.True(File.Exists(file));
        }
        Assert.False(Directory.Exists(Path.GetDirectoryName(oldInstaller)));
        Assert.Equal(0, service.CleanupInstalledUpdates());
    }

    [Fact]
    public void LockedInstallerIsRetriedOnTheNextCleanupWithoutBlockingOtherFiles()
    {
        string installer = CreateFile("1.0.10", "SIDEY-Windows-x64-v1.0.10-Setup.exe");
        string partial = CreateFile("1.0.10", "SIDEY-Windows-x64-v1.0.10-Setup.exe.download");
        var service = new WindowsUpdateService(
            currentProductVersion: "1.0.10",
            currentUpdateVersion: "1.0.10",
            updateCacheDirectory: _cache);

        using (FileStream locked = File.Open(installer, FileMode.Open, FileAccess.Read, FileShare.Read))
        {
            Assert.Equal(1, service.CleanupInstalledUpdates());
            Assert.True(File.Exists(installer));
            Assert.False(File.Exists(partial));
        }

        Assert.Equal(1, service.CleanupInstalledUpdates());
        Assert.False(Directory.Exists(Path.GetDirectoryName(installer)));
    }

    [Fact]
    public void MissingCacheDoesNotGetCreated()
    {
        string missing = Path.Combine(_cache, "missing");
        var service = new WindowsUpdateService(
            currentProductVersion: "1.0.10",
            currentUpdateVersion: "1.0.10",
            updateCacheDirectory: missing);

        Assert.Equal(0, service.CleanupInstalledUpdates());
        Assert.False(Directory.Exists(missing));
    }

    private string CreateFile(string version, string name)
    {
        string directory = Path.Combine(_cache, version);
        Directory.CreateDirectory(directory);
        string file = Path.Combine(directory, name);
        File.WriteAllText(file, "update cleanup fixture");
        return file;
    }

    public void Dispose() => Directory.Delete(_cache, recursive: true);
}
