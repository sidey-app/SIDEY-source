using System.ComponentModel;
using System.Diagnostics;
using System.Net.Http;
using System.Net.Sockets;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Authentication;
using System.Text;
using System.Text.RegularExpressions;
using Sidey.Core.Localization;

namespace Sidey.App.Startup;

internal static class StartupDiagnostics
{
    private const long MaximumLogFileBytes = 4L * 1024 * 1024;
    private const long MaximumLogDirectoryBytes = 32L * 1024 * 1024;
    private const int MaximumLogFileCount = 100;
    private static readonly TimeSpan s_logRetention = TimeSpan.FromDays(30);
    private static readonly TimeSpan s_cleanupInterval = TimeSpan.FromHours(6);
    private static readonly TimeSpan s_runtimeHealthInterval = TimeSpan.FromMinutes(1);
    private static readonly Lock s_gate = new();
    private static readonly Dictionary<string, int> s_errorRepeatCounts = new(StringComparer.Ordinal);
    private static readonly string s_logDirectory = Path.Combine(
        Sidey.Core.Storage.SideyStoragePaths.LocalApplicationDataRoot(),
        "SIDEY",
        "Logs");
    private static string s_logPath = string.Empty;
    private static DateTimeOffset s_lastLogTimestamp = DateTimeOffset.MinValue;
    private static Timer? s_cleanupTimer;
    private static Timer? s_runtimeHealthTimer;
    private static int s_fatalDialogShown;
    private static bool s_logCapacityReached;

    public static void BeginSession()
    {
        lock (s_gate)
        {
            try
            {
                Directory.CreateDirectory(s_logDirectory);
                string? previousLogPath = FindPreviousSessionLog();
                s_logPath = CreateLogPath();
                CleanupLogs();
                s_cleanupTimer ??= new Timer(
                    CleanupOnTimer,
                    null,
                    s_cleanupInterval,
                    s_cleanupInterval);
                AppendLine(
                    $"session-start version={AppVersion()} build={BuildVersion()} "
                    + $"os={Environment.OSVersion.Version} "
                    + $"os-arch={RuntimeInformation.OSArchitecture.ToString().ToLowerInvariant()} "
                    + $"process-arch={RuntimeInformation.ProcessArchitecture.ToString().ToLowerInvariant()} "
                    + $"runtime={RuntimeInformation.FrameworkDescription.Replace(' ', '_')} "
                    + $"processors={Environment.ProcessorCount} time-zone=UTC offset=+00:00");
                if (previousLogPath is not null && !EndedNormally(previousLogPath))
                {
                    AppendLine("previous-session-end result=unclean");
                }
            }
            catch
            {
                // Diagnostics must never become another startup failure.
            }
        }
    }

    public static void MarkRunning()
    {
        lock (s_gate)
        {
            try
            {
                AppendLine("startup-complete");
                AppendLine("runtime-start");
                s_runtimeHealthTimer ??= new Timer(
                    RecordRuntimeHealth,
                    null,
                    s_runtimeHealthInterval,
                    s_runtimeHealthInterval);
            }
            catch
            {
                // Diagnostics must never become another startup failure.
            }
        }
    }

    public static void CompleteSession()
    {
        lock (s_gate)
        {
            try
            {
                AppendLine("shutdown-complete result=normal");
            }
            catch
            {
                // Diagnostics must never prevent shutdown.
            }
            finally
            {
                s_runtimeHealthTimer?.Dispose();
                s_runtimeHealthTimer = null;
                s_cleanupTimer?.Dispose();
                s_cleanupTimer = null;
            }
        }
    }

    public static void Stage(string name) => Write($"stage={name}");

    public static void NonFatal(string stage, Exception exception) =>
        WriteException("non-fatal", stage, exception);

    public static void Fatal(string stage, Exception exception, bool showDialog)
    {
        WriteException("fatal", stage, exception);
        if (showDialog)
        {
            ShowFatalDialog();
        }
    }

    private static void Write(string value)
    {
        lock (s_gate)
        {
            try
            {
                Directory.CreateDirectory(s_logDirectory);
                AppendLine(value);
            }
            catch
            {
                // Best-effort logging only.
            }
        }
    }

    private static void WriteException(string severity, string stage, Exception exception)
    {
        ArgumentNullException.ThrowIfNull(exception);
        var builder = new StringBuilder();
        Exception? current = exception;
        for (int depth = 0; current is not null && depth < 8; depth++)
        {
            if (depth > 0)
            {
                builder.Append(" | inner=");
            }
            builder.Append(current.GetType().FullName);
            builder.Append(" hresult=0x");
            builder.Append(current.HResult.ToString("X8"));
            AppendSafeDetails(builder, current);
            if (!string.IsNullOrWhiteSpace(current.StackTrace))
            {
                builder.Append(" stack=");
                builder.Append(SanitizeStackTrace(current.StackTrace));
            }
            current = current.InnerException;
        }

        string repeatKey = $"{severity}:{stage}:{exception.GetType().FullName}:{exception.HResult:X8}";
        int repeat;
        lock (s_gate)
        {
            repeat = s_errorRepeatCounts.GetValueOrDefault(repeatKey) + 1;
            s_errorRepeatCounts[repeatKey] = repeat;
        }
        Write($"{severity} stage={stage} repeat={repeat} exception={builder}");
    }

    private static void AppendSafeDetails(StringBuilder builder, Exception exception)
    {
        switch (exception)
        {
            case FileNotFoundException fileNotFound when fileNotFound.FileName is { } missingName:
                builder.Append(" file=");
                builder.Append(Path.GetFileName(missingName));
                break;
            case FileLoadException fileLoad when fileLoad.FileName is { } loadName:
                builder.Append(" file=");
                builder.Append(Path.GetFileName(loadName));
                break;
            case BadImageFormatException badImage when badImage.FileName is { } imageName:
                builder.Append(" file=");
                builder.Append(Path.GetFileName(imageName));
                break;
            case TypeInitializationException typeInitialization:
                builder.Append(" type=");
                builder.Append(typeInitialization.TypeName);
                break;
            case TypeLoadException typeLoad when typeLoad.TypeName is { } typeName:
                builder.Append(" type=");
                builder.Append(typeName);
                break;
            case HttpRequestException http:
                builder.Append(" category=http");
                if (http.StatusCode is { } statusCode)
                {
                    builder.Append(" status=");
                    builder.Append((int)statusCode);
                }
                break;
            case SocketException socket:
                builder.Append(" category=");
                builder.Append(IsDnsError(socket.SocketErrorCode) ? "dns" : "socket");
                builder.Append(" socket=");
                builder.Append(socket.SocketErrorCode);
                builder.Append(" native-error=");
                builder.Append(socket.NativeErrorCode);
                break;
            case AuthenticationException:
                builder.Append(" category=tls");
                break;
            case TimeoutException:
                builder.Append(" category=timeout");
                break;
            case TaskCanceledException:
                builder.Append(" category=timeout");
                break;
            case Win32Exception win32:
                builder.Append(" native-error=");
                builder.Append(win32.NativeErrorCode);
                break;
        }
    }

    private static bool IsDnsError(SocketError error) => error is
        SocketError.HostNotFound or SocketError.NoData or SocketError.TryAgain;

    private static string SanitizeStackTrace(string stackTrace) => Regex.Replace(
        stackTrace,
        @" in .*?:line \d+",
        " source-location-redacted",
        RegexOptions.CultureInvariant).ReplaceLineEndings(" <- ");

    private static void AppendLine(string value)
    {
        if (string.IsNullOrEmpty(s_logPath) || s_logCapacityReached)
        {
            return;
        }

        string line = $"{DateTimeOffset.UtcNow:O} pid={Environment.ProcessId} {value}{Environment.NewLine}";
        int lineBytes = Encoding.UTF8.GetByteCount(line);
        if (File.Exists(s_logPath)
            && new FileInfo(s_logPath).Length + lineBytes > MaximumLogFileBytes)
        {
            const string CapacityLine = "log-capacity-reached further-events=discarded";
            string marker = $"{DateTimeOffset.UtcNow:O} pid={Environment.ProcessId} {CapacityLine}{Environment.NewLine}";
            File.AppendAllText(s_logPath, marker, Encoding.UTF8);
            s_logCapacityReached = true;
            return;
        }

        File.AppendAllText(s_logPath, line, Encoding.UTF8);
    }

    private static string CreateLogPath()
    {
        DateTimeOffset timestamp = DateTimeOffset.UtcNow;
        if (timestamp <= s_lastLogTimestamp)
        {
            timestamp = s_lastLogTimestamp.AddSeconds(1);
        }

        string path;
        do
        {
            path = Path.Combine(
                s_logDirectory,
                $"SIDEY.{VersionToken()}.{timestamp:yyyyMMdd}.{timestamp:HHmmss}.log");
            timestamp = timestamp.AddSeconds(1);
        }
        while (File.Exists(path));

        s_lastLogTimestamp = timestamp.AddSeconds(-1);
        return path;
    }

    private static string? FindPreviousSessionLog() => Directory
        .EnumerateFiles(s_logDirectory, "SIDEY.*.log", SearchOption.TopDirectoryOnly)
        .OrderByDescending(File.GetLastWriteTimeUtc)
        .FirstOrDefault();

    private static bool EndedNormally(string path)
    {
        try
        {
            return File.ReadLines(path)
                .TakeLast(32)
                .Any(line => line.Contains(
                    "shutdown-complete result=normal",
                    StringComparison.Ordinal));
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

    private static void RecordRuntimeHealth(object? state)
    {
        _ = state;
        lock (s_gate)
        {
            try
            {
                using var process = Process.GetCurrentProcess();
                uint gdiObjects = OperatingSystem.IsWindows()
                    ? NativeMethods.GetGuiResources(process.Handle, 0)
                    : 0;
                uint userObjects = OperatingSystem.IsWindows()
                    ? NativeMethods.GetGuiResources(process.Handle, 1)
                    : 0;
                AppendLine(
                    $"runtime-health working-set-bytes={process.WorkingSet64} "
                    + $"private-bytes={process.PrivateMemorySize64} "
                    + $"managed-bytes={GC.GetTotalMemory(forceFullCollection: false)} "
                    + $"handles={process.HandleCount} gdi-objects={gdiObjects} user-objects={userObjects}");
            }
            catch
            {
                // Health diagnostics must remain best effort.
            }
        }
    }

    private static void CleanupOnTimer(object? state)
    {
        _ = state;
        lock (s_gate)
        {
            try
            {
                CleanupLogs();
            }
            catch
            {
                // Retention cleanup is best effort.
            }
        }
    }

    private static void CleanupLogs()
    {
        if (!Directory.Exists(s_logDirectory))
        {
            return;
        }

        DateTime retentionThreshold = DateTime.UtcNow - s_logRetention;
        foreach (FileInfo expired in LogFiles()
                     .Where(file => file.LastWriteTimeUtc < retentionThreshold))
        {
            DeleteLog(expired);
        }

        FileInfo[] retained = [.. LogFiles().OrderBy(file => file.LastWriteTimeUtc)];
        long totalBytes = retained.Sum(file => file.Length);
        int fileCount = retained.Length;
        foreach (FileInfo candidate in retained)
        {
            if (fileCount <= MaximumLogFileCount && totalBytes <= MaximumLogDirectoryBytes)
            {
                break;
            }

            if (StringComparer.OrdinalIgnoreCase.Equals(candidate.FullName, s_logPath))
            {
                continue;
            }

            long length = candidate.Length;
            if (DeleteLog(candidate))
            {
                fileCount--;
                totalBytes -= length;
            }
        }
    }

    private static IEnumerable<FileInfo> LogFiles() =>
        new DirectoryInfo(s_logDirectory).EnumerateFiles("*.log", SearchOption.TopDirectoryOnly);

    private static bool DeleteLog(FileInfo file)
    {
        if (StringComparer.OrdinalIgnoreCase.Equals(file.FullName, s_logPath))
        {
            return false;
        }

        try
        {
            file.Delete();
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

    private static string AppVersion() =>
        typeof(App).Assembly.GetName().Version?.ToString(3) ?? "unknown";

    private static string BuildVersion() =>
        typeof(App).Assembly.GetCustomAttribute<AssemblyFileVersionAttribute>()?.Version
        ?? "unknown";

    private static string VersionToken() => AppVersion().Replace('.', '_');

    private static void ShowFatalDialog()
    {
        if (!OperatingSystem.IsWindows()
            || Interlocked.Exchange(ref s_fatalDialogShown, 1) != 0)
        {
            return;
        }

        _ = NativeMethods.MessageBox(
            nint.Zero,
            I18n.Format("app.startup.failed_with_log", s_logPath),
            I18n.Get("app.startup.error.title"),
            0x00000010u | 0x00000000u);
    }

    private static class NativeMethods
    {
        [DllImport("user32.dll", EntryPoint = "MessageBoxW", CharSet = CharSet.Unicode)]
        public static extern int MessageBox(nint window, string text, string caption, uint type);

        [DllImport("user32.dll")]
        public static extern uint GetGuiResources(nint process, uint flags);
    }
}
