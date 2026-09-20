using System.IO.Pipes;
using System.Text;
using Sidey.App.Startup;

namespace Sidey.Platform.Windows.Tests;

public sealed class ForegroundPermissionTransferTests
{
    [Fact]
    public async Task SameUserSecondaryInstanceActivatesThePrimaryInstance()
    {
        string isolationRoot = Path.Combine(
            Path.GetTempPath(),
            $"SIDEY-single-instance-{Guid.NewGuid():N}");
        using var primary = SingleInstanceGuard.Acquire(isolationRoot);
        using var secondary = SingleInstanceGuard.Acquire(isolationRoot);
        var activation = new TaskCompletionSource<string?>(
            TaskCreationOptions.RunContinuationsAsynchronously);
        primary.StartListening(argument => activation.TrySetResult(argument));

        bool delivered = secondary.Signal("activate");

        Assert.True(primary.IsPrimary);
        Assert.False(secondary.IsPrimary);
        Assert.True(delivered);
        Assert.Equal(
            "activate",
            await activation.Task.WaitAsync(TimeSpan.FromSeconds(15)));
    }

    [Fact]
    public async Task SecondaryInstanceGrantsTheExactPipeServerAndStillDeliversActivation()
    {
        string pipeName = $"SIDEY.tests.activate.{Guid.NewGuid():N}";
        await using var server = new NamedPipeServerStream(
            pipeName,
            PipeDirection.In,
            1,
            PipeTransmissionMode.Byte,
            PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);
        var foreground = new FakeSingleInstanceForegroundPermission
        {
            ServerProcessId = 4242,
        };
        Task<bool> signal = Task.Run(() => SingleInstanceGuard.Signal(
            pipeName,
            "sidey://auth/google?code=test",
            foreground));
        await server.WaitForConnectionAsync().WaitAsync(TimeSpan.FromSeconds(10));
        byte[] buffer = new byte[Encoding.UTF8.GetByteCount("sidey://auth/google?code=test")];
        await server.ReadExactlyAsync(buffer).AsTask().WaitAsync(TimeSpan.FromSeconds(10));
        Assert.True(await signal.WaitAsync(TimeSpan.FromSeconds(15)));

        Assert.Equal("sidey://auth/google?code=test", Encoding.UTF8.GetString(buffer));
        Assert.Equal([4242u], foreground.AllowedProcessIds);
    }

    [Fact]
    public async Task ForegroundGrantFailureDoesNotBlockActivationDelivery()
    {
        string pipeName = $"SIDEY.tests.activate.{Guid.NewGuid():N}";
        await using var server = new NamedPipeServerStream(
            pipeName,
            PipeDirection.In,
            1,
            PipeTransmissionMode.Byte,
            PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);
        var foreground = new FakeSingleInstanceForegroundPermission
        {
            ServerProcessId = 4242,
            GrantException = new InvalidOperationException("denied"),
        };
        Task<bool> signal = Task.Run(() => SingleInstanceGuard.Signal(
            pipeName,
            "activate",
            foreground));
        await server.WaitForConnectionAsync().WaitAsync(TimeSpan.FromSeconds(10));
        byte[] buffer = new byte[Encoding.UTF8.GetByteCount("activate")];
        await server.ReadExactlyAsync(buffer).AsTask().WaitAsync(TimeSpan.FromSeconds(10));
        Assert.True(await signal.WaitAsync(TimeSpan.FromSeconds(15)));

        Assert.Equal("activate", Encoding.UTF8.GetString(buffer));
        Assert.Equal([4242u], foreground.AllowedProcessIds);
    }

    [Fact]
    public async Task UntrustedPipeServerReceivesNeitherActivationNorForegroundPermission()
    {
        string pipeName = $"SIDEY.tests.activate.{Guid.NewGuid():N}";
        await using var server = new NamedPipeServerStream(
            pipeName,
            PipeDirection.In,
            1,
            PipeTransmissionMode.Byte,
            PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);
        var foreground = new FakeSingleInstanceForegroundPermission
        {
            ServerProcessId = 4242,
            ExpectedServerUser = false,
        };
        Task<bool> signal = Task.Run(() => SingleInstanceGuard.Signal(
            pipeName,
            "sidey://auth/google?code=secret",
            foreground));
        await server.WaitForConnectionAsync().WaitAsync(TimeSpan.FromSeconds(10));
        byte[] buffer = new byte[64];
        int read = await server.ReadAsync(buffer).AsTask().WaitAsync(TimeSpan.FromSeconds(10));

        Assert.False(await signal.WaitAsync(TimeSpan.FromSeconds(15)));
        Assert.Equal(0, read);
        Assert.Empty(foreground.AllowedProcessIds);
    }

    [Theory]
    [InlineData("unauthorized")]
    [InlineData("io")]
    [InlineData("timeout")]
    public void ExpectedActivationTransportFailuresDoNotCrashSecondaryInstance(string failure)
    {
        Exception exception = failure switch
        {
            "unauthorized" => new UnauthorizedAccessException("denied"),
            "io" => new IOException("closed"),
            "timeout" => new TimeoutException("not ready"),
            _ => throw new ArgumentOutOfRangeException(nameof(failure)),
        };

        bool delivered = SingleInstanceGuard.TryDeliverActivation(() => throw exception);

        Assert.False(delivered);
    }

    [Fact]
    public async Task NativePipeBoundaryReturnsTheConnectedServerProcess()
    {
        string pipeName = $"SIDEY.tests.activate.{Guid.NewGuid():N}";
        await using var server = new NamedPipeServerStream(
            pipeName,
            PipeDirection.In,
            1,
            PipeTransmissionMode.Byte,
            PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);
        using var client = new NamedPipeClientStream(
            ".",
            pipeName,
            PipeDirection.Out,
            PipeOptions.CurrentUserOnly);
        Task connection = server.WaitForConnectionAsync();

        await client.ConnectAsync().WaitAsync(TimeSpan.FromSeconds(10));
        await connection.WaitAsync(TimeSpan.FromSeconds(10));
        var foreground = new NativeSingleInstanceForegroundPermission();

        Assert.True(foreground.TryGetServerProcessId(client, out uint serverProcessId));
        Assert.Equal((uint)Environment.ProcessId, serverProcessId);
        Assert.True(foreground.IsExpectedServerUser(serverProcessId));
    }

    [Fact]
    public void LauncherGrantsTheExactChildProcessWithoutUsingTheWildcard()
    {
        var api = new FakeLauncherForegroundPermissionApi();

        LauncherForegroundPermission.TryGrantToProcess(7319, api);

        Assert.Equal([7319u], api.AllowedProcessIds);
        Assert.DoesNotContain(uint.MaxValue, api.AllowedProcessIds);
    }

    [Fact]
    public void LauncherGrantFailureDoesNotEscapeToBlockHostStartup()
    {
        var api = new FakeLauncherForegroundPermissionApi
        {
            GrantException = new InvalidOperationException("denied"),
        };

        LauncherForegroundPermission.TryGrantToProcess(7319, api);

        Assert.Equal([7319u], api.AllowedProcessIds);
    }

    private sealed class FakeSingleInstanceForegroundPermission : ISingleInstanceForegroundPermission
    {
        internal uint ServerProcessId { get; init; }

        internal Exception? GrantException { get; init; }

        internal bool ExpectedServerUser { get; init; } = true;

        internal List<uint> AllowedProcessIds { get; } = [];

        public bool TryGetServerProcessId(NamedPipeClientStream pipe, out uint processId)
        {
            _ = pipe;
            processId = ServerProcessId;
            return true;
        }

        public bool AllowSetForegroundWindow(uint processId)
        {
            AllowedProcessIds.Add(processId);
            if (GrantException is not null)
            {
                throw GrantException;
            }
            return true;
        }

        public bool IsExpectedServerUser(uint processId)
        {
            Assert.Equal(ServerProcessId, processId);
            return ExpectedServerUser;
        }
    }

    private sealed class FakeLauncherForegroundPermissionApi : ILauncherForegroundPermissionApi
    {
        internal Exception? GrantException { get; init; }

        internal List<uint> AllowedProcessIds { get; } = [];

        public bool AllowSetForegroundWindow(uint processId)
        {
            AllowedProcessIds.Add(processId);
            if (GrantException is not null)
            {
                throw GrantException;
            }
            return true;
        }
    }
}
