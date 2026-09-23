using System.Runtime.CompilerServices;
using Sidey.Core.Abstractions;
using Sidey.Core.Domain;
using Sidey.Infrastructure.Authentication;
using Sidey.Infrastructure.Realtime;

namespace Sidey.Platform.Windows.Tests;

public sealed class FirebaseV2RealtimeTransportTests
{
    private static readonly Guid s_roomId = Guid.Parse("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
    private static readonly Guid s_messageId = Guid.Parse("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb");
    private static readonly Guid s_userId = Guid.Parse("cccccccc-cccc-cccc-cccc-cccccccccccc");
    private static readonly Guid s_otherRoomId = Guid.Parse("eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee");

    [Fact]
    public async Task DisabledServerSelectionKeepsLegacyAndDoesNotOpenFirebase()
    {
        var legacy = new FakeLegacyTransport();
        var listener = new FakeFirebaseListener();
        await using var transport = new FirebaseV2RealtimeTransport(
            legacy,
            new FakeSelector(enabled: false),
            new FakeChatClient(),
            new FakeCredentialProvider(),
            sink => listener.WithSink(sink));

        await transport.SynchronizeAsync(
            new Dictionary<Guid, long> { [s_roomId] = 1 },
            s_roomId,
            PresenceState.Online,
            CancellationToken.None);

        Assert.False(transport.UsesFirebaseChat);
        Assert.Equal(1, legacy.SynchronizeCount);
        Assert.Equal(0, listener.StartCount);
        Assert.True(listener.StopCount >= 1);
    }

    [Fact]
    public async Task EnabledServerSelectionOpensFirebaseAndUsesCallableChat()
    {
        var legacy = new FakeLegacyTransport();
        var listener = new FakeFirebaseListener();
        var chat = new FakeChatClient();
        await using var transport = new FirebaseV2RealtimeTransport(
            legacy,
            new FakeSelector(enabled: true),
            chat,
            new FakeCredentialProvider(),
            sink => listener.WithSink(sink));

        await transport.SynchronizeAsync(
            new Dictionary<Guid, long> { [s_roomId] = 1 },
            s_roomId,
            PresenceState.Online,
            CancellationToken.None);
        FirebaseRealtimeChatResult? result = await transport.PublishChatAsync(
            s_messageId,
            s_roomId,
            "hello",
            CancellationToken.None);

        Assert.True(transport.UsesFirebaseChat);
        Assert.True(transport.ConnectionStatus.IsReady);
        Assert.Equal(1, listener.StartCount);
        Assert.Equal(s_roomId, listener.ActiveRoomId);
        Assert.Equal(1, chat.SendCount);
        Assert.Equal(s_messageId, result?.MessageId);
    }

    [Fact]
    public async Task ChatRequiresReadyListenerAndActiveRoom()
    {
        var listener = new FakeFirebaseListener { PublishReadyOnStart = false };
        var chat = new FakeChatClient();
        await using var transport = new FirebaseV2RealtimeTransport(
            new FakeLegacyTransport(),
            new FakeSelector(enabled: true),
            chat,
            new FakeCredentialProvider(),
            sink => listener.WithSink(sink));
        await transport.SynchronizeAsync(
            new Dictionary<Guid, long> { [s_roomId] = 1 },
            s_roomId,
            PresenceState.Online,
            CancellationToken.None);

        await Assert.ThrowsAsync<InvalidOperationException>(() => transport.PublishChatAsync(
            s_messageId,
            s_roomId,
            "not-ready",
            CancellationToken.None));
        listener.PublishReady();
        await Assert.ThrowsAsync<InvalidOperationException>(() => transport.PublishChatAsync(
            s_messageId,
            s_otherRoomId,
            "wrong-room",
            CancellationToken.None));

        Assert.Equal(0, chat.SendCount);
    }

    [Fact]
    public async Task ExplicitSessionInvalidationResetsFirebaseCredentialGeneration()
    {
        var credentials = new FakeCredentialProvider();
        var transport = new FirebaseV2RealtimeTransport(
            new FakeLegacyTransport(),
            new FakeSelector(enabled: true),
            new FakeChatClient(),
            credentials,
            sink => new FakeFirebaseListener().WithSink(sink));
        await transport.SynchronizeAsync(
            new Dictionary<Guid, long> { [s_roomId] = 1 },
            s_roomId,
            PresenceState.Online,
            CancellationToken.None);

        await transport.InvalidateSessionAsync();

        Assert.Equal(1, credentials.ResetCount);
        await transport.DisposeAsync();
        Assert.Equal(1, credentials.ResetCount);

        await Assert.ThrowsAsync<ObjectDisposedException>(() => transport.PublishChatAsync(
            s_messageId,
            s_roomId,
            "blocked",
            CancellationToken.None));
        await Assert.ThrowsAsync<ObjectDisposedException>(() => transport.ConvergeGrantAsync(
            "00000000000000000003",
            CancellationToken.None));
    }

    [Fact]
    public async Task GrantConvergenceFailureStopsFirebaseWithoutTurningCommittedMutationIntoFailure()
    {
        var listener = new FakeFirebaseListener();
        var credentials = new FakeCredentialProvider
        {
            ConvergeFailure = new HttpRequestException("offline"),
        };
        await using var transport = new FirebaseV2RealtimeTransport(
            new FakeLegacyTransport(),
            new FakeSelector(enabled: true),
            new FakeChatClient(),
            credentials,
            sink => listener.WithSink(sink));
        await transport.SynchronizeAsync(
            new Dictionary<Guid, long> { [s_roomId] = 1 },
            s_roomId,
            PresenceState.Online,
            CancellationToken.None);

        await transport.ConvergeGrantAsync(
            "00000000000000000002",
            CancellationToken.None);

        Assert.True(transport.UsesFirebaseChat);
        Assert.False(transport.ConnectionStatus.IsReady);
        Assert.True(listener.StopCount >= 1);
    }

    [Fact]
    public async Task SessionInvalidationCancelsChatThatAlreadyPassedTheTerminalFence()
    {
        var chat = new FakeChatClient { Block = true };
        await using var transport = new FirebaseV2RealtimeTransport(
            new FakeLegacyTransport(),
            new FakeSelector(enabled: true),
            chat,
            new FakeCredentialProvider(),
            sink => new FakeFirebaseListener().WithSink(sink));
        await transport.SynchronizeAsync(
            new Dictionary<Guid, long> { [s_roomId] = 1 },
            s_roomId,
            PresenceState.Online,
            CancellationToken.None);
        Task<FirebaseRealtimeChatResult?> pending = transport.PublishChatAsync(
            s_messageId,
            s_roomId,
            "hello",
            CancellationToken.None);
        await chat.Started.Task.WaitAsync(TimeSpan.FromSeconds(5));

        await transport.InvalidateSessionAsync();

        await Assert.ThrowsAnyAsync<OperationCanceledException>(
            () => pending.WaitAsync(TimeSpan.FromSeconds(5)));
    }

    [Fact]
    public async Task ActiveRoomChangeMarksInFlightChatCommitAmbiguous()
    {
        var chat = new FakeChatClient { Block = true };
        await using var transport = new FirebaseV2RealtimeTransport(
            new FakeLegacyTransport(),
            new FakeSelector(enabled: true),
            chat,
            new FakeCredentialProvider(),
            sink => new FakeFirebaseListener().WithSink(sink));
        await transport.SynchronizeAsync(
            new Dictionary<Guid, long> { [s_roomId] = 1, [s_otherRoomId] = 1 },
            s_roomId,
            PresenceState.Online,
            CancellationToken.None);
        Task<FirebaseRealtimeChatResult?> pending = transport.PublishChatAsync(
            s_messageId,
            s_roomId,
            "hello",
            CancellationToken.None);
        await chat.Started.Task.WaitAsync(TimeSpan.FromSeconds(5));

        await transport.SynchronizeAsync(
            new Dictionary<Guid, long> { [s_roomId] = 1, [s_otherRoomId] = 1 },
            s_otherRoomId,
            PresenceState.Online,
            CancellationToken.None);

        FirebaseRealtimeChatException exception =
            await Assert.ThrowsAsync<FirebaseRealtimeChatException>(
                () => pending.WaitAsync(TimeSpan.FromSeconds(5)));
        Assert.Equal(
            FirebaseRealtimeChatFailureClassification.CommitAmbiguous,
            exception.Classification);
        Assert.Equal("transport-canceled", exception.Code);
    }

    [Fact]
    public async Task DisconnectAfterCallableCommitMarksResponseWaitAmbiguous()
    {
        var chat = new FakeChatClient { Block = true };
        var listener = new FakeFirebaseListener();
        await using var transport = new FirebaseV2RealtimeTransport(
            new FakeLegacyTransport(),
            new FakeSelector(enabled: true),
            chat,
            new FakeCredentialProvider(),
            sink => listener.WithSink(sink));
        await transport.SynchronizeAsync(
            new Dictionary<Guid, long> { [s_roomId] = 1 },
            s_roomId,
            PresenceState.Online,
            CancellationToken.None);
        Task<FirebaseRealtimeChatResult?> pending = transport.PublishChatAsync(
            s_messageId,
            s_roomId,
            "hello",
            CancellationToken.None);
        await chat.Started.Task.WaitAsync(TimeSpan.FromSeconds(5));

        listener.PublishDisconnected();

        FirebaseRealtimeChatException exception =
            await Assert.ThrowsAsync<FirebaseRealtimeChatException>(
                () => pending.WaitAsync(TimeSpan.FromSeconds(5)));
        Assert.Equal(
            FirebaseRealtimeChatFailureClassification.CommitAmbiguous,
            exception.Classification);
        Assert.Equal("transport-canceled", exception.Code);
    }

    [Fact]
    public async Task CallerCancellationPreservesCancellationSemanticsForInFlightChat()
    {
        var chat = new FakeChatClient { Block = true };
        await using var transport = new FirebaseV2RealtimeTransport(
            new FakeLegacyTransport(),
            new FakeSelector(enabled: true),
            chat,
            new FakeCredentialProvider(),
            sink => new FakeFirebaseListener().WithSink(sink));
        await transport.SynchronizeAsync(
            new Dictionary<Guid, long> { [s_roomId] = 1 },
            s_roomId,
            PresenceState.Online,
            CancellationToken.None);
        using var cancellation = new CancellationTokenSource();
        Task<FirebaseRealtimeChatResult?> pending = transport.PublishChatAsync(
            s_messageId,
            s_roomId,
            "hello",
            cancellation.Token);
        await chat.Started.Task.WaitAsync(TimeSpan.FromSeconds(5));

        cancellation.Cancel();

        await Assert.ThrowsAnyAsync<OperationCanceledException>(
            () => pending.WaitAsync(TimeSpan.FromSeconds(5)));
    }

    [Fact]
    public async Task SelectorFailureStopsListenerAndFailsClosedForReadsAndWrites()
    {
        var selector = new FakeSelector(enabled: true)
        {
            CacheTtl = TimeSpan.FromMilliseconds(100),
            RefreshFailure = new HttpRequestException("offline"),
        };
        var listener = new FakeFirebaseListener();
        await using var transport = new FirebaseV2RealtimeTransport(
            new FakeLegacyTransport(),
            selector,
            new FakeChatClient(),
            new FakeCredentialProvider(),
            sink => listener.WithSink(sink));
        await transport.SynchronizeAsync(
            new Dictionary<Guid, long> { [s_roomId] = 1 },
            s_roomId,
            PresenceState.Online,
            CancellationToken.None);
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(5));
        List<BackendEvent> received = [];
        var reader = Task.Run(async () =>
        {
            await foreach (BackendEvent backendEvent in transport.ReadEventsAsync(timeout.Token))
            {
                received.Add(backendEvent);
                if (backendEvent is BackendEvent.Diagnostic
                    { Stage: "after-selector-failure" })
                {
                    break;
                }
            }
        });
        await selector.RefreshAttempted.Task.WaitAsync(TimeSpan.FromSeconds(5));
        await WaitUntilAsync(() => listener.StopCount >= 1);
        listener.Publish(new BackendEvent.CharacterPulsed(
            new CharacterPulseEvent(Guid.NewGuid(), s_roomId, s_userId)));
        listener.Publish(new BackendEvent.Diagnostic("after-selector-failure"));
        await reader.WaitAsync(TimeSpan.FromSeconds(5));

        Assert.False(transport.ConnectionStatus.IsReady);
        Assert.DoesNotContain(received, item => item is BackendEvent.CharacterPulsed);
        await Assert.ThrowsAsync<InvalidOperationException>(() => transport.PublishChatAsync(
            s_messageId,
            s_roomId,
            "blocked",
            CancellationToken.None));
    }

    [Fact]
    public async Task GrantConvergenceFailureWakesLongSelectorDelayForImmediateRecovery()
    {
        var selector = new FakeSelector(enabled: true) { CacheTtl = TimeSpan.FromHours(1) };
        var listener = new FakeFirebaseListener();
        var credentials = new FakeCredentialProvider
        {
            ConvergeFailure = new HttpRequestException("offline"),
        };
        await using var transport = new FirebaseV2RealtimeTransport(
            new FakeLegacyTransport(),
            selector,
            new FakeChatClient(),
            credentials,
            sink => listener.WithSink(sink));
        await transport.SynchronizeAsync(
            new Dictionary<Guid, long> { [s_roomId] = 1 },
            s_roomId,
            PresenceState.Online,
            CancellationToken.None);

        await transport.ConvergeGrantAsync("00000000000000000002", CancellationToken.None);

        await selector.RefreshAttempted.Task.WaitAsync(TimeSpan.FromSeconds(5));
        await WaitUntilAsync(() => listener.StartCount >= 2);
        Assert.True(transport.ConnectionStatus.IsReady);
    }

    [Fact]
    public async Task EnabledSelectionPublishesAllTransientActionsThroughFirebase()
    {
        var transients = new FakeTransientClient();
        await using var transport = new FirebaseV2RealtimeTransport(
            new FakeLegacyTransport(),
            new FakeSelector(enabled: true),
            new FakeChatClient(),
            new FakeCredentialProvider(),
            sink => new FakeFirebaseListener().WithSink(sink),
            transients);
        transport.ConfigureThrowableWireCodes(new Dictionary<string, string>
        {
            ["throwable_leaf"] = "18",
        });
        await transport.SynchronizeAsync(
            new Dictionary<Guid, long> { [s_roomId] = 1 },
            s_roomId,
            PresenceState.Online,
            CancellationToken.None);

        await transport.PublishTypingAsync(s_roomId, active: true, CancellationToken.None);
        await transport.PublishCharacterPulseAsync(s_roomId, CancellationToken.None);
        await transport.PublishCharacterThrowAsync(
            s_roomId,
            s_userId,
            "throwable_leaf",
            CancellationToken.None);

        Assert.Equal(1, transients.TypingCount);
        Assert.Equal(1, transients.PulseCount);
        Assert.Equal(1, transients.ThrowCount);
        Assert.Equal("18", transients.LastWireCode);
    }

    [Fact]
    public async Task EnabledSelectionDropsLegacyTransientMirrorEvents()
    {
        BackendEvent.Diagnostic sentinel = new("legacy-sentinel");
        var legacy = new FakeLegacyTransport(
        [
            new BackendEvent.TypingChanged(s_roomId, s_userId, true),
            new BackendEvent.CharacterPulsed(
                new CharacterPulseEvent(Guid.NewGuid(), s_roomId, s_userId)),
            new BackendEvent.CharacterThrown(new CharacterThrowEvent(
                Guid.NewGuid(),
                s_roomId,
                s_userId,
                Guid.NewGuid(),
                "pixel_hamster")),
            sentinel,
        ]);
        await using var transport = new FirebaseV2RealtimeTransport(
            legacy,
            new FakeSelector(enabled: true),
            new FakeChatClient(),
            new FakeCredentialProvider(),
            sink => new FakeFirebaseListener().WithSink(sink),
            new FakeTransientClient());
        await transport.SynchronizeAsync(
            new Dictionary<Guid, long> { [s_roomId] = 1 },
            s_roomId,
            PresenceState.Online,
            CancellationToken.None);

        List<BackendEvent> received = [];
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(5));
        await foreach (BackendEvent backendEvent in transport.ReadEventsAsync(timeout.Token))
        {
            received.Add(backendEvent);
            if (ReferenceEquals(backendEvent, sentinel))
            {
                break;
            }
        }

        Assert.DoesNotContain(received, item => item is BackendEvent.TypingChanged
            or BackendEvent.CharacterPulsed
            or BackendEvent.CharacterThrown);
    }

    private sealed class FakeSelector(bool enabled) : IFirebaseRealtimeRolloutSelector
    {
        public TimeSpan CacheTtl { get; init; } = TimeSpan.FromMinutes(5);
        public Exception? RefreshFailure { get; init; }
        public TaskCompletionSource RefreshAttempted { get; } =
            new(TaskCreationOptions.RunContinuationsAsynchronously);

        public ValueTask<FirebaseRealtimeRolloutSelection> SelectAsync(
            CancellationToken cancellationToken = default)
        {
            cancellationToken.ThrowIfCancellationRequested();
            return ValueTask.FromResult(new FirebaseRealtimeRolloutSelection(
                enabled
                    ? FirebaseRealtimeSelectedTransport.FirebaseV2
                    : FirebaseRealtimeSelectedTransport.LegacySupabase,
                killSwitch: !enabled,
                CacheTtl,
                FirebaseRealtimeRolloutSelectionSource.Server));
        }

        public ValueTask<FirebaseRealtimeRolloutSelection> RefreshAsync(
            CancellationToken cancellationToken = default)
        {
            cancellationToken.ThrowIfCancellationRequested();
            RefreshAttempted.TrySetResult();
            return RefreshFailure is null
                ? SelectAsync(cancellationToken)
                : ValueTask.FromException<FirebaseRealtimeRolloutSelection>(RefreshFailure);
        }
    }

    private sealed class FakeChatClient : IFirebaseRealtimeChatClient
    {
        public int SendCount { get; private set; }
        public bool Block { get; init; }
        public TaskCompletionSource Started { get; } =
            new(TaskCreationOptions.RunContinuationsAsynchronously);

        public async ValueTask<FirebaseRealtimeChatResult> SendAsync(
            Guid messageId,
            Guid roomId,
            string body,
            CancellationToken cancellationToken = default)
        {
            cancellationToken.ThrowIfCancellationRequested();
            SendCount++;
            Started.TrySetResult();
            if (Block)
            {
                await Task.Delay(Timeout.InfiniteTimeSpan, cancellationToken);
            }
            return new FirebaseRealtimeChatResult(
                messageId,
                roomId,
                s_userId,
                body,
                1_750_000_000_000,
                sequence: 1,
                bubbleWireCode: null);
        }
    }

    private sealed class FakeCredentialProvider : IFirebaseRealtimeCredentialProvider
    {
        public int ResetCount { get; private set; }
        public Exception? ConvergeFailure { get; init; }

        public ValueTask<FirebaseRealtimeCredential> GetCredentialAsync(
            CancellationToken cancellationToken = default) =>
            ValueTask.FromResult(new FirebaseRealtimeCredential(
                s_userId,
                Guid.Parse("dddddddd-dddd-dddd-dddd-dddddddddddd"),
                "token",
                new Uri("https://sidey.asia-southeast1.firebasedatabase.app"),
                generation: 1));

        public ValueTask<FirebaseRealtimeCredential> ConvergeAsync(
            string minimumAccessRevision,
            CancellationToken cancellationToken = default) =>
            ConvergeFailure is null
                ? GetCredentialAsync(cancellationToken)
                : ValueTask.FromException<FirebaseRealtimeCredential>(ConvergeFailure);

        public ValueTask ResetAsync(CancellationToken cancellationToken = default)
        {
            cancellationToken.ThrowIfCancellationRequested();
            ResetCount++;
            return ValueTask.CompletedTask;
        }
    }

    private sealed class FakeFirebaseListener : IFirebaseRealtimeListener
    {
        private Action<BackendEvent>? _sink;

        public bool IsReady { get; private set; }
        public int StartCount { get; private set; }
        public int StopCount { get; private set; }
        public Guid? ActiveRoomId { get; private set; }
        public bool PublishReadyOnStart { get; init; } = true;

        public FakeFirebaseListener WithSink(Action<BackendEvent> sink)
        {
            _sink = sink;
            return this;
        }

        public Task StartAsync(Guid? activeRoomId, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            StartCount++;
            ActiveRoomId = activeRoomId;
            if (PublishReadyOnStart)
            {
                PublishReady();
            }
            return Task.CompletedTask;
        }

        public Task StopAsync(CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            StopCount++;
            IsReady = false;
            _sink?.Invoke(new BackendEvent.ConnectionChanged(RealtimeConnectionStatus.Disconnected));
            return Task.CompletedTask;
        }

        public void PublishReady()
        {
            IsReady = true;
            _sink?.Invoke(new BackendEvent.ConnectionChanged(
                new RealtimeConnectionStatus(true, true, true)));
        }

        public void PublishDisconnected()
        {
            IsReady = false;
            _sink?.Invoke(new BackendEvent.ConnectionChanged(
                RealtimeConnectionStatus.Disconnected));
        }

        public void Publish(BackendEvent backendEvent) => _sink?.Invoke(backendEvent);

        public void RequestReconnect()
        {
        }

        public ValueTask DisposeAsync()
        {
            IsReady = false;
            return ValueTask.CompletedTask;
        }
    }

    private sealed class FakeTransientClient : IFirebaseRealtimeTransientClient
    {
        public int TypingCount { get; private set; }
        public int PulseCount { get; private set; }
        public int ThrowCount { get; private set; }
        public string? LastWireCode { get; private set; }

        public Task PublishTypingAsync(
            Guid roomId,
            bool active,
            CancellationToken cancellationToken)
        {
            TypingCount++;
            return Task.CompletedTask;
        }

        public Task PublishCharacterPulseAsync(Guid roomId, CancellationToken cancellationToken)
        {
            PulseCount++;
            return Task.CompletedTask;
        }

        public Task PublishCharacterThrowAsync(
            Guid roomId,
            Guid targetUserId,
            string wireCode,
            CancellationToken cancellationToken)
        {
            ThrowCount++;
            LastWireCode = wireCode;
            return Task.CompletedTask;
        }
    }

    private sealed class FakeLegacyTransport(
        IReadOnlyList<BackendEvent>? events = null) : IRealtimeTransport
    {
        public int SynchronizeCount { get; private set; }
        public RealtimeConnectionStatus ConnectionStatus { get; } = new(true, true, true);
        public bool IsRecoveryPaused => false;

        public async IAsyncEnumerable<BackendEvent> ReadEventsAsync(
            [EnumeratorCancellation] CancellationToken cancellationToken)
        {
            foreach (BackendEvent backendEvent in events ?? [])
            {
                yield return backendEvent;
            }
            await Task.Delay(Timeout.InfiniteTimeSpan, cancellationToken);
            yield break;
        }

        public Task SynchronizeAsync(
            IReadOnlyDictionary<Guid, long> roomEpochs,
            Guid? activeRoomId,
            PresenceState localPresence,
            CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            SynchronizeCount++;
            return Task.CompletedTask;
        }

        public Task PublishPresenceAsync(
            Guid roomId,
            PresenceState state,
            CancellationToken cancellationToken) => Task.CompletedTask;

        public async Task<bool> RunWhileConnectedAsync(
            Func<CancellationToken, Task> operation,
            CancellationToken cancellationToken)
        {
            await operation(cancellationToken);
            return true;
        }

        public void RequestReconnect(bool userInitiated = false)
        {
        }

        public ValueTask DisposeAsync() => ValueTask.CompletedTask;
    }

    private static async Task WaitUntilAsync(Func<bool> predicate)
    {
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(5));
        while (!predicate())
        {
            await Task.Delay(10, timeout.Token);
        }
    }
}
