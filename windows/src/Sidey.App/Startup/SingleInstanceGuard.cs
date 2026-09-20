using System.IO.Pipes;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Text;
using Microsoft.Win32.SafeHandles;

namespace Sidey.App.Startup;

internal sealed class SingleInstanceGuard : IDisposable
{
    private const string MutexName = "Local\\SIDEY.app.sidey.desktop";
    private const string ActivationPipeName = "SIDEY.app.sidey.desktop.activate";
    private const int MaximumActivationBytes = 4096;
    private readonly Mutex _mutex;
    private readonly string _activationPipeName;
    private readonly ISingleInstanceForegroundPermission _foregroundPermission;
    private readonly CancellationTokenSource _listening = new();
    private Task? _activationTask;

    private SingleInstanceGuard(
        Mutex mutex,
        bool isPrimary,
        string activationPipeName,
        ISingleInstanceForegroundPermission foregroundPermission)
    {
        _mutex = mutex;
        IsPrimary = isPrimary;
        _activationPipeName = activationPipeName;
        _foregroundPermission = foregroundPermission;
    }

    public bool IsPrimary { get; }

    public static SingleInstanceGuard Acquire(string? smokeDataRoot = null)
    {
        // The startup harness already isolates its data; isolate activation too so it cannot target a user's app.
        string suffix = string.IsNullOrWhiteSpace(smokeDataRoot) ? string.Empty
            : ".smoke." + Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(Encoding.UTF8.GetBytes(smokeDataRoot)))[..24];
        var mutex = new Mutex(initiallyOwned: true, MutexName + suffix, out bool createdNew);
        return new SingleInstanceGuard(
            mutex,
            createdNew,
            ActivationPipeName + suffix,
            new NativeSingleInstanceForegroundPermission());
    }

    public void StartListening(Action<string?> activate)
    {
        if (!IsPrimary || _activationTask is not null)
        {
            return;
        }

        ArgumentNullException.ThrowIfNull(activate);
        _activationTask = Task.Run(() => ListenAsync(activate, _listening.Token));
    }

    public bool Signal(string? activationArgument)
    {
        return Signal(_activationPipeName, activationArgument, _foregroundPermission);
    }

    internal static bool Signal(
        string activationPipeName,
        string? activationArgument,
        ISingleInstanceForegroundPermission foregroundPermission)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(activationPipeName);
        ArgumentNullException.ThrowIfNull(foregroundPermission);
        byte[] payload = Encoding.UTF8.GetBytes(activationArgument ?? string.Empty);
        if (payload.Length > MaximumActivationBytes)
        {
            payload = [];
        }
        return TryDeliverActivation(() =>
        {
            using var pipe = new NamedPipeClientStream(
                ".",
                activationPipeName,
                PipeDirection.Out,
                PipeOptions.None);
            pipe.Connect(10000);
            if (!TryAuthorizeServer(pipe, foregroundPermission))
            {
                throw new UnauthorizedAccessException(
                    "The activation pipe server does not belong to the current Windows user.");
            }
            pipe.Write(payload);
        });
    }

    internal static bool TryDeliverActivation(Action deliver)
    {
        ArgumentNullException.ThrowIfNull(deliver);
        try
        {
            deliver();
            return true;
        }
        catch (Exception exception) when (exception is UnauthorizedAccessException
            or IOException
            or TimeoutException)
        {
            System.Diagnostics.Trace.TraceWarning(
                "SIDEY secondary activation delivery failed: {0}",
                exception);
            return false;
        }
    }

    private static bool TryAuthorizeServer(
        NamedPipeClientStream pipe,
        ISingleInstanceForegroundPermission foregroundPermission)
    {
        uint processId;
        try
        {
            if (!foregroundPermission.TryGetServerProcessId(pipe, out processId)
                || processId == 0
                || !foregroundPermission.IsExpectedServerUser(processId))
                return false;
        }
        catch (Exception)
        {
            return false;
        }

        try
        {
            _ = foregroundPermission.AllowSetForegroundWindow(processId);
        }
        catch (Exception)
        {
            // Foreground permission is best effort after the server identity is verified.
        }
        return true;
    }

    private async Task ListenAsync(
        Action<string?> activate,
        CancellationToken cancellationToken)
    {
        while (!cancellationToken.IsCancellationRequested)
        {
            try
            {
                await using NamedPipeServerStream pipe = CreateActivationServer(
                    _activationPipeName);
                await pipe.WaitForConnectionAsync(cancellationToken);
                byte[] buffer = new byte[MaximumActivationBytes + 1];
                int count = 0;
                while (count < buffer.Length)
                {
                    int read = await pipe.ReadAsync(buffer.AsMemory(count), cancellationToken);
                    if (read == 0)
                    {
                        break;
                    }
                    count += read;
                }
                string? argument = count is 0 or > MaximumActivationBytes
                    ? null
                    : Encoding.UTF8.GetString(buffer, 0, count);
                activate(argument);
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                return;
            }
            catch (IOException)
            {
            }
        }
    }

    private static NamedPipeServerStream CreateActivationServer(string pipeName)
    {
        SecurityIdentifier user = WindowsIdentity.GetCurrent().User
            ?? throw new InvalidOperationException("The current Windows user SID is unavailable.");
        var security = new PipeSecurity();
        security.SetOwner(user);
        security.SetAccessRuleProtection(isProtected: true, preserveInheritance: false);
        security.AddAccessRule(new PipeAccessRule(
            user,
            PipeAccessRights.FullControl,
            AccessControlType.Allow));
        return NamedPipeServerStreamAcl.Create(
            pipeName,
            PipeDirection.In,
            1,
            PipeTransmissionMode.Byte,
            PipeOptions.Asynchronous,
            0,
            0,
            security);
    }

    public void Dispose()
    {
        _listening.Cancel();
        if (IsPrimary)
        {
            try
            {
                _mutex.ReleaseMutex();
            }
            catch (ApplicationException)
            {
            }
        }
        _listening.Dispose();
        _mutex.Dispose();
    }
}

internal interface ISingleInstanceForegroundPermission
{
    public bool TryGetServerProcessId(NamedPipeClientStream pipe, out uint processId);

    public bool IsExpectedServerUser(uint processId);

    public bool AllowSetForegroundWindow(uint processId);
}

internal sealed class NativeSingleInstanceForegroundPermission : ISingleInstanceForegroundPermission
{
    public bool TryGetServerProcessId(NamedPipeClientStream pipe, out uint processId) =>
        NativeMethods.GetNamedPipeServerProcessId(pipe.SafePipeHandle, out processId);

    public bool IsExpectedServerUser(uint processId)
    {
        try
        {
            using SafeProcessHandle process = NativeMethods.OpenProcess(
                NativeMethods.ProcessQueryLimitedInformation,
                inheritHandle: false,
                processId);
            if (process.IsInvalid)
                return false;
            if (!NativeMethods.OpenProcessToken(
                process,
                NativeMethods.TokenQuery,
                out SafeAccessTokenHandle token))
                return false;
            using (token)
            using (var server = new WindowsIdentity(token.DangerousGetHandle()))
            using (var current = WindowsIdentity.GetCurrent())
            {
                SecurityIdentifier? serverUser = server.User;
                SecurityIdentifier? currentUser = current.User;
                return serverUser is not null
                    && currentUser is not null
                    && serverUser.Equals(currentUser);
            }
        }
        catch (Exception exception) when (exception is ArgumentException
            or InvalidOperationException
            or System.ComponentModel.Win32Exception)
        {
            return false;
        }
    }

    public bool AllowSetForegroundWindow(uint processId) =>
        NativeMethods.AllowSetForegroundWindow(processId);

    private static class NativeMethods
    {
        internal const uint ProcessQueryLimitedInformation = 0x1000;
        internal const uint TokenQuery = 0x0008;

        [DllImport("kernel32.dll", SetLastError = true)]
        internal static extern SafeProcessHandle OpenProcess(
            uint desiredAccess,
            [MarshalAs(UnmanagedType.Bool)] bool inheritHandle,
            uint processId);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool GetNamedPipeServerProcessId(
            Microsoft.Win32.SafeHandles.SafePipeHandle pipe,
            out uint serverProcessId);

        [DllImport("advapi32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool OpenProcessToken(
            SafeProcessHandle processHandle,
            uint desiredAccess,
            out SafeAccessTokenHandle tokenHandle);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool AllowSetForegroundWindow(uint processId);
    }
}
