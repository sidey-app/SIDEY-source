using System.Net;
using System.Text;
using System.Text.Json;
using Sidey.Core.Abstractions;
using Sidey.Core.Domain;
using Sidey.Infrastructure.Authentication;
using Sidey.Infrastructure.Realtime;

namespace Sidey.Platform.Windows.Tests;

public sealed class FirebaseRealtimeListenerTests
{
    private static readonly Guid s_userId = Guid.Parse("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
    private static readonly Guid s_sessionId = Guid.Parse("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb");
    private static readonly Guid s_roomId = Guid.Parse("cccccccc-cccc-cccc-cccc-cccccccccccc");

    [Fact]
    public async Task CredentialRefreshDeadlineRotatesWithoutDisconnectingHealthyStreams()
    {
        var time = new TimerTimeProvider();
        var release = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var events = new System.Collections.Concurrent.ConcurrentQueue<BackendEvent>();
        var credentials = new ScriptedCredentialProvider(async (request, token) =>
        {
            if (request > 1)
            {
                await release.Task.WaitAsync(token);
            }
            return ScheduledCredential(request == 1 ? 10 : 270, request == 1 ? 30 : 300);
        });
        await using var listener = new FirebaseRealtimeListener(credentials, events.Enqueue, _ => CreateClient(), time);
        await listener.StartAsync(s_roomId, CancellationToken.None);
        await WaitUntilAsync(() => listener.IsReady && time.ActiveTimers >= 2);
        events.Clear();

        time.Advance(TimeSpan.FromSeconds(10));
        await WaitUntilAsync(() => credentials.RequestCount == 2);
        Assert.True(listener.IsReady);
        release.SetResult();
        await WaitUntilAsync(() => events.OfType<BackendEvent.Diagnostic>().Any(item =>
            item.Stage.StartsWith("firebase-listener-ready", StringComparison.Ordinal)));

        Assert.True(listener.IsReady);
        Assert.DoesNotContain(events, item => item is BackendEvent.ConnectionChanged { Status.ActiveRoomTransportConnected: false });
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task OldStreamFailureOrLeaseExpiryClearsReadinessDuringBlockedRenewal(bool expireLease)
    {
        var time = new TimerTimeProvider();
        var release = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var endOldStream = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var credentials = new ScriptedCredentialProvider(async (request, token) =>
        {
            if (request > 1)
            {
                await release.Task.WaitAsync(token);
            }
            return ScheduledCredential(request == 1 ? 10 : 270, request == 1 ? 15 : 300);
        });
        int clients = 0;
        await using var listener = new FirebaseRealtimeListener(
            credentials,
            _ => { },
            _ => CreateClient(Interlocked.Increment(ref clients) == 1 ? endOldStream.Task : Task.Delay(Timeout.InfiniteTimeSpan)),
            time);
        await listener.StartAsync(s_roomId, CancellationToken.None);
        await WaitUntilAsync(() => listener.IsReady && time.ActiveTimers >= 2);
        time.Advance(TimeSpan.FromSeconds(10));
        await WaitUntilAsync(() => credentials.RequestCount == 2);

        if (expireLease)
        {
            time.Advance(TimeSpan.FromSeconds(5));
        }
        else
        {
            endOldStream.SetResult();
        }
        await WaitUntilAsync(() => !listener.IsReady);
        release.SetResult();
        await WaitUntilAsync(() => listener.IsReady);
        Assert.Equal(2, clients);
    }

    [Fact]
    public async Task InitialConnectionDeadlineIncludesCredentialAcquisition()
    {
        var time = new TimerTimeProvider();
        var cancelled = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var credentials = new ScriptedCredentialProvider(async (_, token) =>
        {
            try
            {
                await Task.Delay(Timeout.InfiniteTimeSpan, token);
            }
            catch (OperationCanceledException)
            {
                cancelled.TrySetResult();
                throw;
            }
            return ScheduledCredential(270, 300);
        });
        await using var listener = new FirebaseRealtimeListener(credentials, _ => { }, _ => CreateClient(), time);
        await listener.StartAsync(s_roomId, CancellationToken.None);
        await WaitUntilAsync(() => credentials.RequestCount == 1);
        time.Advance(TimeSpan.FromSeconds(20));
        await cancelled.Task.WaitAsync(TimeSpan.FromSeconds(3));
        Assert.False(listener.IsReady);
        await listener.StopAsync(CancellationToken.None);
    }

    [Fact]
    public async Task LeaseExpiryDiscardsPartiallyReadyCandidateBeforeRebuildingLiveBaseline()
    {
        var time = new TimerTimeProvider();
        var events = new System.Collections.Concurrent.ConcurrentQueue<BackendEvent>();
        var peer = Guid.Parse("eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee");
        var credentials = new ScriptedCredentialProvider((request, _) => ValueTask.FromResult(
            ScheduledCredential(request == 1 ? 10 : 270, request == 1 ? 15 : 300)));
        int clients = 0;
        int candidateStreamsDisposed = 0;
        await using var listener = new FirebaseRealtimeListener(credentials, events.Enqueue, _ =>
        {
            int client = Interlocked.Increment(ref clients);
            if (client == 1)
            {
                return CreateClient();
            }
            if (client == 3)
            {
                return CreateClient(Task.Delay(Timeout.InfiniteTimeSpan),
                    RoomTransientEvents(peer, s_userId, time.GetUtcNow().ToUnixTimeMilliseconds()));
            }
            var urls = new FirebaseRtdbUrlBuilder(new Uri("https://sidey.asia-southeast1.firebasedatabase.app"));
            return FirebaseRtdbRestClient.CreateForTesting(urls, (request, _) =>
            {
                bool inbox = request.RequestUri!.AbsolutePath.Contains("/v2/n/", StringComparison.Ordinal);
                string prefix = inbox ? string.Empty : TypingRoomEvents(peer, time.GetUtcNow().ToUnixTimeMilliseconds());
                return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK)
                {
                    Content = new StreamContent(new PrefixThenWaitStream(Encoding.UTF8.GetBytes(prefix),
                        () => Interlocked.Increment(ref candidateStreamsDisposed))),
                });
            });
        }, time);
        await listener.StartAsync(s_roomId, CancellationToken.None);
        await WaitUntilAsync(() => listener.IsReady && time.ActiveTimers >= 2);
        time.Advance(TimeSpan.FromSeconds(10));
        await WaitUntilAsync(() => events.OfType<BackendEvent.TypingChanged>().Any(item => item.Active));

        time.Advance(TimeSpan.FromSeconds(5));
        await WaitUntilAsync(() => clients == 3 && listener.IsReady
            && events.OfType<BackendEvent.CharacterPulsed>().Any());
        Assert.Equal(2, candidateStreamsDisposed);
        Assert.Contains(events, item => item is BackendEvent.TypingChanged { Active: false });
        Assert.Single(events.OfType<BackendEvent.CharacterPulsed>());
    }

    [Fact]
    public async Task InitialSnapshotsAreBaselinesAndHigherChatHintInvalidatesOnce()
    {
        var events = new List<BackendEvent>();
        object eventGate = new();
        var credentials = new FakeCredentialProvider();
        await using var listener = new FirebaseRealtimeListener(
            credentials,
            backendEvent =>
            {
                lock (eventGate)
                {
                    events.Add(backendEvent);
                }
            },
            _ => CreateClient());

        await listener.StartAsync(s_roomId, CancellationToken.None);
        await WaitUntilAsync(() => listener.IsReady);
        await WaitUntilAsync(() =>
        {
            lock (eventGate)
            {
                return events.OfType<BackendEvent.MessagesInvalidated>().Any();
            }
        });

        BackendEvent.MessagesInvalidated[] invalidations;
        lock (eventGate)
        {
            invalidations = [.. events.OfType<BackendEvent.MessagesInvalidated>()];
        }
        Assert.Single(invalidations);
        Assert.Equal(s_roomId, invalidations[0].RoomId);
        Assert.DoesNotContain(events, item => item is BackendEvent.TechnicalError);
    }

    [Fact]
    public async Task StopCancelsBothStreamsAndClearsReadiness()
    {
        var credentials = new FakeCredentialProvider();
        await using var listener = new FirebaseRealtimeListener(
            credentials,
            _ => { },
            _ => CreateClient());

        await listener.StartAsync(s_roomId, CancellationToken.None);
        await WaitUntilAsync(() => listener.IsReady);

        await listener.StopAsync(CancellationToken.None);

        Assert.False(listener.IsReady);
        Assert.Equal(1, credentials.RequestCount);
    }

    [Fact]
    public async Task ProductionAccessOnlyInboxReachesReadyState()
    {
        var events = new List<BackendEvent>();
        object eventGate = new();
        await using var listener = new FirebaseRealtimeListener(
            new FakeCredentialProvider(),
            backendEvent =>
            {
                lock (eventGate)
                {
                    events.Add(backendEvent);
                }
            },
            _ => CreateClient(
                Task.Delay(Timeout.InfiniteTimeSpan),
                RoomEvents(),
                AccessOnlyInboxEvents()));

        await listener.StartAsync(s_roomId, CancellationToken.None);
        await WaitUntilAsync(() => listener.IsReady);

        lock (eventGate)
        {
            Assert.Contains(events, item => item is BackendEvent.Diagnostic diagnostic
                && diagnostic.Stage.StartsWith("firebase-listener-ready", StringComparison.Ordinal));
            Assert.DoesNotContain(events, item => item is BackendEvent.Diagnostic diagnostic
                && diagnostic.Stage.StartsWith("firebase-listener-connect-failed", StringComparison.Ordinal));
        }
    }

    [Fact]
    public async Task MissingProductionInboxReachesReadyState()
    {
        var events = new List<BackendEvent>();
        object eventGate = new();
        await using var listener = new FirebaseRealtimeListener(
            new FakeCredentialProvider(),
            backendEvent =>
            {
                lock (eventGate)
                {
                    events.Add(backendEvent);
                }
            },
            _ => CreateClient(
                Task.Delay(Timeout.InfiniteTimeSpan),
                RoomEvents(),
                NullInboxEvents()));

        await listener.StartAsync(s_roomId, CancellationToken.None);
        await WaitUntilAsync(() => listener.IsReady);

        lock (eventGate)
        {
            Assert.Contains(events, item => item is BackendEvent.Diagnostic diagnostic
                && diagnostic.Stage.StartsWith("firebase-listener-ready", StringComparison.Ordinal));
            Assert.DoesNotContain(events, item => item is BackendEvent.Diagnostic diagnostic
                && diagnostic.Stage.StartsWith("firebase-listener-connect-failed", StringComparison.Ordinal));
        }
    }

    [Fact]
    public async Task MalformedSnapshotIsIgnoredUntilAValidSnapshotArrives()
    {
        var events = new List<BackendEvent>();
        object eventGate = new();
        await using var listener = new FirebaseRealtimeListener(
            new FakeCredentialProvider(),
            backendEvent =>
            {
                lock (eventGate)
                {
                    events.Add(backendEvent);
                }
            },
            _ => CreateClient(
                Task.Delay(Timeout.InfiniteTimeSpan),
                RoomEvents(),
                MalformedThenValidInboxEvents()));

        await listener.StartAsync(s_roomId, CancellationToken.None);
        await WaitUntilAsync(() => listener.IsReady);
        await WaitUntilAsync(() =>
        {
            lock (eventGate)
            {
                return events.OfType<BackendEvent.Diagnostic>().Any(diagnostic =>
                    diagnostic.Stage == "firebase-listener-snapshot-ignored kind=protocol stream=inbox");
            }
        });

        lock (eventGate)
        {
            Assert.Contains(events, item => item is BackendEvent.Diagnostic diagnostic
                && diagnostic.Stage == "firebase-listener-snapshot-ignored kind=protocol stream=inbox");
            Assert.Contains(events, item => item is BackendEvent.Diagnostic diagnostic
                && diagnostic.Stage.StartsWith("firebase-listener-ready", StringComparison.Ordinal));
            Assert.DoesNotContain(events, item => item is BackendEvent.Diagnostic diagnostic
                && diagnostic.Stage.StartsWith("firebase-listener-connect-failed", StringComparison.Ordinal));
        }
    }

    [Fact]
    public async Task InitialStreamEofDiagnosticIdentifiesStreamWithoutPayload()
    {
        var events = new List<BackendEvent>();
        object eventGate = new();
        await using var listener = new FirebaseRealtimeListener(
            new FakeCredentialProvider(),
            backendEvent =>
            {
                lock (eventGate)
                {
                    events.Add(backendEvent);
                }
            },
            _ => CreateClient(
                Task.FromResult(0),
                string.Empty,
                InboxEvents()));

        await listener.StartAsync(s_roomId, CancellationToken.None);
        await WaitUntilAsync(() =>
        {
            lock (eventGate)
            {
                return events.OfType<BackendEvent.Diagnostic>().Any(diagnostic =>
                    diagnostic.Stage == "firebase-listener-connect-failed kind=eof stream=room phase=initial");
            }
        });
    }

    [Fact]
    public async Task CredentialProtocolDiagnosticIdentifiesStageWithoutPayload()
    {
        var events = new List<BackendEvent>();
        object eventGate = new();
        await using var listener = new FirebaseRealtimeListener(
            new MalformedCredentialProvider(),
            backendEvent =>
            {
                lock (eventGate)
                {
                    events.Add(backendEvent);
                }
            });

        await listener.StartAsync(s_roomId, CancellationToken.None);
        await WaitUntilAsync(() =>
        {
            lock (eventGate)
            {
                return events.OfType<BackendEvent.Diagnostic>().Any(diagnostic =>
                    diagnostic.Stage == "firebase-listener-connect-failed kind=protocol stage=credential");
            }
        });
    }

    [Fact]
    public async Task CredentialProtocolDiagnosticIdentifiesSafeSubstageWithoutPayload()
    {
        var events = new List<BackendEvent>();
        object eventGate = new();
        await using var listener = new FirebaseRealtimeListener(
            new StagedMalformedCredentialProvider(),
            backendEvent =>
            {
                lock (eventGate)
                {
                    events.Add(backendEvent);
                }
            });

        await listener.StartAsync(s_roomId, CancellationToken.None);
        await WaitUntilAsync(() =>
        {
            lock (eventGate)
            {
                return events.OfType<BackendEvent.Diagnostic>().Any(diagnostic =>
                    diagnostic.Stage ==
                    "firebase-listener-connect-failed kind=protocol stage=credential detail=bootstrap-response")
                    && events.OfType<BackendEvent.Diagnostic>().All(diagnostic =>
                        !diagnostic.Stage.Contains("secret credential payload", StringComparison.Ordinal));
            }
        });
    }

    [Fact]
    public async Task StreamRequestDiagnosticIdentifiesStageStatusAndStreamWithoutPayload()
    {
        var events = new List<BackendEvent>();
        object eventGate = new();
        await using var listener = new FirebaseRealtimeListener(
            new FakeCredentialProvider(),
            backendEvent =>
            {
                lock (eventGate)
                {
                    events.Add(backendEvent);
                }
            },
            _ => CreateProtocolFailureClient());

        await listener.StartAsync(activeRoomId: null, CancellationToken.None);
        await WaitUntilAsync(() =>
        {
            lock (eventGate)
            {
                return events.OfType<BackendEvent.Diagnostic>().Any(diagnostic =>
                    diagnostic.Stage == "firebase-listener-connect-failed kind=protocol stream=inbox stage=request status=400");
            }
        });
    }

    [Fact]
    public async Task ReconnectsWhenEitherActiveStreamEnds()
    {
        var credentials = new FakeCredentialProvider();
        var roomEnd = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        await using var listener = new FirebaseRealtimeListener(
            credentials,
            _ => { },
            _ => CreateClient(roomEnd.Task));

        await listener.StartAsync(s_roomId, CancellationToken.None);
        await WaitUntilAsync(() => listener.IsReady);

        roomEnd.TrySetResult();

        await WaitUntilAsync(() => credentials.RequestCount >= 2);
    }

    [Fact]
    public async Task ReadyStreamEofPublishesDisconnectedStatusAndClearsPeerTyping()
    {
        var peerUserId = Guid.Parse("eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee");
        long now = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
        var roomEnd = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var events = new List<BackendEvent>();
        object eventGate = new();
        await using var listener = new FirebaseRealtimeListener(
            new FakeCredentialProvider(),
            backendEvent =>
            {
                lock (eventGate)
                {
                    events.Add(backendEvent);
                }
            },
            _ => CreateClient(roomEnd.Task, TypingRoomEvents(peerUserId, now)));

        await listener.StartAsync(s_roomId, CancellationToken.None);
        await WaitUntilAsync(() => listener.IsReady);
        await WaitUntilAsync(() =>
        {
            lock (eventGate)
            {
                return events.OfType<BackendEvent.TypingChanged>()
                    .Any(item => item.UserId == peerUserId && item.Active);
            }
        });

        roomEnd.TrySetResult();

        await WaitUntilAsync(() =>
        {
            lock (eventGate)
            {
                return events.OfType<BackendEvent.ConnectionChanged>()
                        .Any(item => !item.Status.IsReady)
                    && events.OfType<BackendEvent.TypingChanged>()
                        .Any(item => item.UserId == peerUserId && !item.Active);
            }
        });
        Assert.False(listener.IsReady);
        lock (eventGate)
        {
            Assert.Contains(events, item => item is BackendEvent.ConnectionChanged
            { Status.IsReady: true });
            Assert.Contains(events, item => item is BackendEvent.Diagnostic diagnostic
                && diagnostic.Stage == "firebase-listener-disconnected kind=eof stream=room phase=active");
        }
    }

    [Fact]
    public async Task ReadyStreamAuthRevocationPublishesDisconnectedStatus()
    {
        var revoke = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var events = new List<BackendEvent>();
        object eventGate = new();
        await using var listener = new FirebaseRealtimeListener(
            new FakeCredentialProvider(),
            backendEvent =>
            {
                lock (eventGate)
                {
                    events.Add(backendEvent);
                }
            },
            _ => CreateAuthRevokingClient(revoke.Task));

        await listener.StartAsync(s_roomId, CancellationToken.None);
        await WaitUntilAsync(() => listener.IsReady);

        revoke.TrySetResult();

        await WaitUntilAsync(() =>
        {
            lock (eventGate)
            {
                return events.OfType<BackendEvent.Diagnostic>().Any(diagnostic =>
                    diagnostic.Stage == "firebase-listener-disconnected kind=access-denied");
            }
        });
        Assert.False(listener.IsReady);
        lock (eventGate)
        {
            Assert.Contains(events, item => item is BackendEvent.ConnectionChanged
            { Status.IsReady: false });
        }
    }

    [Fact]
    public async Task DisconnectWaitsForInFlightTypingEmitBeforePublishingStatusAndCleanup()
    {
        var peerUserId = Guid.Parse("eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee");
        long now = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
        var publishTyping = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var endInbox = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var typingEntered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var allowTyping = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var events = new List<BackendEvent>();
        object eventGate = new();
        await using var listener = new FirebaseRealtimeListener(
            new FakeCredentialProvider(),
            backendEvent =>
            {
                if (backendEvent is BackendEvent.TypingChanged { Active: true })
                {
                    typingEntered.TrySetResult();
                    allowTyping.Task.GetAwaiter().GetResult();
                }
                lock (eventGate)
                {
                    events.Add(backendEvent);
                }
            },
            _ => CreateTypingRaceClient(
                endInbox.Task,
                publishTyping.Task,
                peerUserId,
                now));

        await listener.StartAsync(s_roomId, CancellationToken.None);
        await WaitUntilAsync(() => listener.IsReady);
        publishTyping.TrySetResult();
        await typingEntered.Task.WaitAsync(TimeSpan.FromSeconds(5));

        endInbox.TrySetResult();
        try
        {
            await Task.Delay(100);
            lock (eventGate)
            {
                Assert.DoesNotContain(events, item => item is BackendEvent.ConnectionChanged
                { Status.IsReady: false });
            }
        }
        finally
        {
            allowTyping.TrySetResult();
        }

        await WaitUntilAsync(() =>
        {
            lock (eventGate)
            {
                return events.OfType<BackendEvent.TypingChanged>()
                        .Any(item => item.UserId == peerUserId && !item.Active)
                    && events.OfType<BackendEvent.ConnectionChanged>()
                        .Any(item => !item.Status.IsReady);
            }
        });
        lock (eventGate)
        {
            int typingOn = events.FindIndex(item => item is BackendEvent.TypingChanged
            { UserId: var userId, Active: true } && userId == peerUserId);
            int disconnected = events.FindIndex(item => item is BackendEvent.ConnectionChanged
            { Status.IsReady: false });
            int typingOff = events.FindIndex(item => item is BackendEvent.TypingChanged
            { UserId: var userId, Active: false } && userId == peerUserId);
            Assert.True(typingOn >= 0 && typingOn < disconnected);
            Assert.True(disconnected < typingOff);
        }
    }

    [Fact]
    public async Task InitialConnectionFailureDrainsPartialRoomAndClearsTyping()
    {
        var peerUserId = Guid.Parse("eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee");
        long now = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
        var allowInboxFailure = new TaskCompletionSource(
            TaskCreationOptions.RunContinuationsAsynchronously);
        var typingObserved = new TaskCompletionSource(
            TaskCreationOptions.RunContinuationsAsynchronously);
        var events = new List<BackendEvent>();
        object eventGate = new();
        await using var listener = new FirebaseRealtimeListener(
            new FakeCredentialProvider(),
            backendEvent =>
            {
                lock (eventGate)
                {
                    events.Add(backendEvent);
                }
                if (backendEvent is BackendEvent.TypingChanged { Active: true })
                {
                    typingObserved.TrySetResult();
                }
            },
            _ => CreatePartialFailureClient(
                allowInboxFailure.Task,
                peerUserId,
                now));

        await listener.StartAsync(s_roomId, CancellationToken.None);
        await typingObserved.Task.WaitAsync(TimeSpan.FromSeconds(5));
        allowInboxFailure.TrySetResult();

        await WaitUntilAsync(() =>
        {
            lock (eventGate)
            {
                return events.OfType<BackendEvent.Diagnostic>().Any(diagnostic =>
                        diagnostic.Stage == "firebase-listener-connect-failed kind=eof stream=inbox phase=initial")
                    && events.OfType<BackendEvent.TypingChanged>()
                        .Any(item => item.UserId == peerUserId && !item.Active);
            }
        });
        Assert.False(listener.IsReady);
    }

    [Fact]
    public async Task FreshFirebasePulseAndThrowSnapshotsEmitPeerActions()
    {
        var actorUserId = Guid.Parse("eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee");
        var targetUserId = Guid.Parse("ffffffff-ffff-ffff-ffff-ffffffffffff");
        long now = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
        var events = new List<BackendEvent>();
        object eventGate = new();
        await using var listener = new FirebaseRealtimeListener(
            new FakeCredentialProvider(),
            backendEvent =>
            {
                lock (eventGate)
                {
                    events.Add(backendEvent);
                }
            },
            _ => CreateClient(
                Task.Delay(Timeout.InfiniteTimeSpan),
                RoomTransientEvents(actorUserId, targetUserId, now)));
        listener.ConfigureThrowableWireCodes(new Dictionary<string, string>
        {
            ["18"] = "throwable_leaf",
        });

        await listener.StartAsync(s_roomId, CancellationToken.None);
        await WaitUntilAsync(() =>
        {
            lock (eventGate)
            {
                return events.OfType<BackendEvent.CharacterPulsed>().Any()
                    && events.OfType<BackendEvent.CharacterThrown>().Any();
            }
        });

        lock (eventGate)
        {
            string[] diagnostics = [.. events.OfType<BackendEvent.Diagnostic>()
                .Select(item => item.Stage)];
            Assert.Contains("firebase-live-baseline pulse=1 throw=1", diagnostics);
            Assert.Contains("firebase-live-pulse result=accepted", diagnostics);
            Assert.Contains("firebase-live-throw result=accepted", diagnostics);
            Assert.DoesNotContain(diagnostics,
                item => item.Contains(actorUserId.ToString("D"), StringComparison.Ordinal));
            Assert.Equal(actorUserId, Assert.Single(
                events.OfType<BackendEvent.CharacterPulsed>()).Pulse.UserId);
            CharacterThrowEvent characterThrow = Assert.Single(
                events.OfType<BackendEvent.CharacterThrown>()).Throw;
            Assert.Equal(actorUserId, characterThrow.ActorUserId);
            Assert.Equal(targetUserId, characterThrow.TargetUserId);
            Assert.Equal("throwable_leaf", characterThrow.ThrowableId);
        }
    }

    private static FirebaseRtdbRestClient CreateClient()
        => CreateClient(Task.Delay(Timeout.InfiniteTimeSpan));

    private static FirebaseRtdbRestClient CreateClient(Task roomEnd) =>
        CreateClient(roomEnd, RoomEvents());

    private static FirebaseRtdbRestClient CreateClient(Task roomEnd, string roomEvents)
        => CreateClient(roomEnd, roomEvents, InboxEvents());

    private static FirebaseRtdbRestClient CreateClient(
        Task roomEnd,
        string roomEvents,
        string inboxEvents)
    {
        var urls = new FirebaseRtdbUrlBuilder(
            new Uri("https://sidey.asia-southeast1.firebasedatabase.app"));
        return FirebaseRtdbRestClient.CreateForTesting(urls, (request, _) =>
        {
            string path = request.RequestUri!.AbsolutePath;
            string content = path.Contains("/v2/n/", StringComparison.Ordinal)
                ? inboxEvents
                : roomEvents;
            Stream stream = path.Contains("/v2/n/", StringComparison.Ordinal)
                ? new PrefixThenWaitStream(Encoding.UTF8.GetBytes(content))
                : new PrefixThenSignalStream(Encoding.UTF8.GetBytes(content), roomEnd);
            var response = new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StreamContent(stream),
            };
            return Task.FromResult(response);
        });
    }

    private static FirebaseRtdbRestClient CreateAuthRevokingClient(Task revoke)
    {
        var urls = new FirebaseRtdbUrlBuilder(
            new Uri("https://sidey.asia-southeast1.firebasedatabase.app"));
        return FirebaseRtdbRestClient.CreateForTesting(urls, (request, _) =>
        {
            bool inbox = request.RequestUri!.AbsolutePath.Contains(
                "/v2/n/",
                StringComparison.Ordinal);
            Stream stream = inbox
                ? new PrefixThenWaitStream(Encoding.UTF8.GetBytes(InboxEvents()))
                : new PrefixThenSuffixStream(
                    Encoding.UTF8.GetBytes(RoomEvents()),
                    Encoding.UTF8.GetBytes(
                        "event: auth_revoked\ndata: \"expired\"\n\n"),
                    revoke);
            var response = new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StreamContent(stream),
            };
            return Task.FromResult(response);
        });
    }

    private static FirebaseRtdbRestClient CreateTypingRaceClient(
        Task endInbox,
        Task publishTyping,
        Guid peerUserId,
        long timestamp)
    {
        var urls = new FirebaseRtdbUrlBuilder(
            new Uri("https://sidey.asia-southeast1.firebasedatabase.app"));
        return FirebaseRtdbRestClient.CreateForTesting(urls, (request, _) =>
        {
            bool inbox = request.RequestUri!.AbsolutePath.Contains(
                "/v2/n/",
                StringComparison.Ordinal);
            Stream stream = inbox
                ? new PrefixThenSignalStream(Encoding.UTF8.GetBytes(InboxEvents()), endInbox)
                : new PrefixThenSuffixStream(
                    Encoding.UTF8.GetBytes(RoomEvents()),
                    Encoding.UTF8.GetBytes(TypingPatchEvent(peerUserId, timestamp)),
                    publishTyping);
            var response = new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StreamContent(stream),
            };
            return Task.FromResult(response);
        });
    }

    private static FirebaseRtdbRestClient CreatePartialFailureClient(
        Task allowInboxFailure,
        Guid peerUserId,
        long timestamp)
    {
        var urls = new FirebaseRtdbUrlBuilder(
            new Uri("https://sidey.asia-southeast1.firebasedatabase.app"));
        return FirebaseRtdbRestClient.CreateForTesting(urls, (request, _) =>
        {
            bool inbox = request.RequestUri!.AbsolutePath.Contains(
                "/v2/n/",
                StringComparison.Ordinal);
            Stream stream = inbox
                ? new PrefixThenSignalStream(
                    Encoding.UTF8.GetBytes(MalformedInboxEvents()),
                    allowInboxFailure)
                : new PrefixThenWaitStream(Encoding.UTF8.GetBytes(
                    TypingRoomEvents(peerUserId, timestamp)));
            var response = new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StreamContent(stream),
            };
            return Task.FromResult(response);
        });
    }

    private static string AccessOnlyInboxEvents()
    {
        string initial = JsonSerializer.Serialize(new
        {
            path = "/",
            data = new { a = "00000000000000000001" },
        });
        return $"event: put\ndata: {initial}\n\n";
    }

    private static string NullInboxEvents()
    {
        string initial = JsonSerializer.Serialize(new
        {
            path = "/",
            data = (object?)null,
        });
        return $"event: put\ndata: {initial}\n\n";
    }

    private static string MalformedInboxEvents()
    {
        string initial = JsonSerializer.Serialize(new
        {
            path = "/",
            data = false,
        });
        return $"event: put\ndata: {initial}\n\n";
    }

    private static string MalformedThenValidInboxEvents() =>
        MalformedInboxEvents() + InboxEvents();

    private static FirebaseRtdbRestClient CreateProtocolFailureClient()
    {
        var urls = new FirebaseRtdbUrlBuilder(
            new Uri("https://sidey.asia-southeast1.firebasedatabase.app"));
        return FirebaseRtdbRestClient.CreateForTesting(urls, (_, _) =>
            Task.FromResult(new HttpResponseMessage(HttpStatusCode.BadRequest)));
    }

    private static string InboxEvents()
    {
        string roomId = s_roomId.ToString("D");
        string initial = JsonSerializer.Serialize(new
        {
            path = "/",
            data = new
            {
                a = "00000000000000000001",
                r = new Dictionary<string, object>
                {
                    [roomId] = new { v = "00000000000000000001", n = 1 },
                },
            },
        });
        string update = JsonSerializer.Serialize(new
        {
            path = $"/r/{roomId}",
            data = new { n = 2 },
        });
        return $"event: put\ndata: {initial}\n\nevent: patch\ndata: {update}\n\n";
    }

    private static string RoomEvents()
    {
        string messageId = Guid.Parse("dddddddd-dddd-dddd-dddd-dddddddddddd").ToString("D");
        string initial = JsonSerializer.Serialize(new
        {
            path = "/",
            data = new
            {
                e = new
                {
                    i = messageId,
                    s = s_userId,
                    b = "hello",
                    t = 1_750_000_000_000,
                    n = 1,
                },
            },
        });
        return $"event: put\ndata: {initial}\n\n";
    }

    private static string RoomTransientEvents(Guid actorUserId, Guid targetUserId, long now)
    {
        long baselineTimestamp = now - 1_000;
        string actor = actorUserId.ToString("D");
        string initial = JsonSerializer.Serialize(new
        {
            path = "/",
            data = new
            {
                c = new Dictionary<string, long> { [actor] = baselineTimestamp },
                x = new Dictionary<string, object>
                {
                    [actor] = new { u = targetUserId, k = "18", t = baselineTimestamp },
                },
            },
        });
        string pulse = JsonSerializer.Serialize(new
        {
            path = $"/c/{actor}",
            data = now,
        });
        string characterThrow = JsonSerializer.Serialize(new
        {
            path = $"/x/{actor}",
            data = new { u = targetUserId, k = "18", t = now },
        });
        return $"event: put\ndata: {initial}\n\n"
            + $"event: put\ndata: {pulse}\n\n"
            + $"event: put\ndata: {characterThrow}\n\n";
    }

    private static string TypingRoomEvents(Guid userId, long timestamp)
    {
        string user = userId.ToString("D");
        string session = Guid.Parse("ffffffff-ffff-ffff-ffff-ffffffffffff").ToString("D");
        string initial = JsonSerializer.Serialize(new
        {
            path = "/",
            data = new
            {
                t = new Dictionary<string, object>
                {
                    [user] = new Dictionary<string, long> { [session] = timestamp },
                },
            },
        });
        return $"event: put\ndata: {initial}\n\n";
    }

    private static string TypingPatchEvent(Guid userId, long timestamp)
    {
        string user = userId.ToString("D");
        string session = Guid.Parse("ffffffff-ffff-ffff-ffff-ffffffffffff").ToString("D");
        string update = JsonSerializer.Serialize(new
        {
            path = $"/t/{user}/{session}",
            data = timestamp,
        });
        return $"event: put\ndata: {update}\n\n";
    }

    private static async Task WaitUntilAsync(Func<bool> predicate)
    {
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(5));
        while (!predicate())
        {
            await Task.Delay(10, timeout.Token);
        }
    }

    private static FirebaseRealtimeCredential ScheduledCredential(int refreshSeconds, int expirySeconds) => new(
        s_userId, s_sessionId, "id-token", new Uri("https://sidey.asia-southeast1.firebasedatabase.app"), 1,
        refreshAfter: TimeSpan.FromSeconds(refreshSeconds), expiresAfter: TimeSpan.FromSeconds(expirySeconds));

    private sealed class ScriptedCredentialProvider(
        Func<int, CancellationToken, ValueTask<FirebaseRealtimeCredential>> acquire) : IFirebaseRealtimeCredentialProvider
    {
        private int _requests;
        public int RequestCount => Volatile.Read(ref _requests);
        public ValueTask<FirebaseRealtimeCredential> GetCredentialAsync(CancellationToken cancellationToken = default) =>
            acquire(Interlocked.Increment(ref _requests), cancellationToken);
        public ValueTask ResetAsync(CancellationToken cancellationToken = default) => ValueTask.CompletedTask;
    }

    private sealed class TimerTimeProvider : TimeProvider
    {
        private readonly Lock _gate = new();
        private readonly List<ManualTimer> _timers = [];
        private long _timestamp;
        public override long TimestampFrequency => TimeSpan.TicksPerSecond;
        public override long GetTimestamp() { lock (_gate) return _timestamp; }
        public override DateTimeOffset GetUtcNow() => DateTimeOffset.FromUnixTimeMilliseconds(1_750_000_000_000).AddTicks(GetTimestamp());
        public int ActiveTimers { get { lock (_gate) return _timers.Count(timer => timer.DueAt != long.MaxValue); } }
        public override ITimer CreateTimer(TimerCallback callback, object? state, TimeSpan dueTime, TimeSpan period)
        {
            var timer = new ManualTimer(this, callback, state);
            lock (_gate)
            {
                _timers.Add(timer);
                timer.Change(dueTime, period);
            }
            return timer;
        }
        public void Advance(TimeSpan elapsed)
        {
            ManualTimer[] due;
            lock (_gate)
            {
                _timestamp += elapsed.Ticks;
                due = [.. _timers.Where(timer => timer.DueAt <= _timestamp)];
                foreach (ManualTimer timer in due)
                    timer.DueAt = long.MaxValue;
            }
            foreach (ManualTimer timer in due)
                timer.Fire();
        }
        private sealed class ManualTimer(TimerTimeProvider owner, TimerCallback callback, object? state) : ITimer
        {
            public long DueAt { get; set; } = long.MaxValue;
            public bool Change(TimeSpan dueTime, TimeSpan period)
            {
                lock (owner._gate)
                    DueAt = dueTime == Timeout.InfiniteTimeSpan ? long.MaxValue : owner._timestamp + dueTime.Ticks;
                return true;
            }
            public void Fire() => callback(state);
            public void Dispose() { lock (owner._gate) DueAt = long.MaxValue; }
            public ValueTask DisposeAsync() { Dispose(); return ValueTask.CompletedTask; }
        }
    }

    private sealed class FakeCredentialProvider : IFirebaseRealtimeCredentialProvider
    {
        public int RequestCount { get; private set; }

        public ValueTask<FirebaseRealtimeCredential> GetCredentialAsync(
            CancellationToken cancellationToken = default)
        {
            cancellationToken.ThrowIfCancellationRequested();
            RequestCount++;
            return ValueTask.FromResult(new FirebaseRealtimeCredential(
                s_userId,
                s_sessionId,
                "id-token",
                new Uri("https://sidey.asia-southeast1.firebasedatabase.app"),
                generation: 1));
        }

        public ValueTask ResetAsync(CancellationToken cancellationToken = default) =>
            ValueTask.CompletedTask;
    }

    private sealed class MalformedCredentialProvider : IFirebaseRealtimeCredentialProvider
    {
        public ValueTask<FirebaseRealtimeCredential> GetCredentialAsync(
            CancellationToken cancellationToken = default) =>
            ValueTask.FromException<FirebaseRealtimeCredential>(
                new InvalidDataException("secret credential payload"));

        public ValueTask ResetAsync(CancellationToken cancellationToken = default) =>
            ValueTask.CompletedTask;
    }

    private sealed class StagedMalformedCredentialProvider : IFirebaseRealtimeCredentialProvider
    {
        public ValueTask<FirebaseRealtimeCredential> GetCredentialAsync(
            CancellationToken cancellationToken = default) =>
            ValueTask.FromException<FirebaseRealtimeCredential>(
                new FirebaseRealtimeCredentialStageException(
                    "bootstrap-response",
                    new InvalidDataException("secret credential payload")));

        public ValueTask ResetAsync(CancellationToken cancellationToken = default) =>
            ValueTask.CompletedTask;
    }

    private sealed class PrefixThenWaitStream(byte[] prefix, Action? onDispose = null) : Stream
    {
        private int _offset;
        private int _disposed;

        public override bool CanRead => true;
        public override bool CanSeek => false;
        public override bool CanWrite => false;
        public override long Length => throw new NotSupportedException();
        public override long Position
        {
            get => throw new NotSupportedException();
            set => throw new NotSupportedException();
        }

        public override int Read(byte[] buffer, int offset, int count) =>
            throw new NotSupportedException();

        public override async ValueTask<int> ReadAsync(
            Memory<byte> buffer,
            CancellationToken cancellationToken = default)
        {
            if (_offset < prefix.Length)
            {
                int count = Math.Min(buffer.Length, prefix.Length - _offset);
                prefix.AsMemory(_offset, count).CopyTo(buffer);
                _offset += count;
                return count;
            }

            await Task.Delay(Timeout.InfiniteTimeSpan, cancellationToken);
            return 0;
        }

        public override void Flush() => throw new NotSupportedException();
        protected override void Dispose(bool disposing)
        {
            if (disposing && Interlocked.Exchange(ref _disposed, 1) == 0)
                onDispose?.Invoke();
            base.Dispose(disposing);
        }
        public override long Seek(long offset, SeekOrigin origin) => throw new NotSupportedException();
        public override void SetLength(long value) => throw new NotSupportedException();
        public override void Write(byte[] buffer, int offset, int count) => throw new NotSupportedException();
    }

    private sealed class PrefixThenSignalStream(byte[] prefix, Task end) : Stream
    {
        private int _offset;

        public override bool CanRead => true;
        public override bool CanSeek => false;
        public override bool CanWrite => false;
        public override long Length => throw new NotSupportedException();
        public override long Position
        {
            get => throw new NotSupportedException();
            set => throw new NotSupportedException();
        }

        public override int Read(byte[] buffer, int offset, int count) =>
            throw new NotSupportedException();

        public override async ValueTask<int> ReadAsync(
            Memory<byte> buffer,
            CancellationToken cancellationToken = default)
        {
            if (_offset < prefix.Length)
            {
                int count = Math.Min(buffer.Length, prefix.Length - _offset);
                prefix.AsMemory(_offset, count).CopyTo(buffer);
                _offset += count;
                return count;
            }

            await end.WaitAsync(cancellationToken);
            return 0;
        }

        public override void Flush() => throw new NotSupportedException();
        public override long Seek(long offset, SeekOrigin origin) => throw new NotSupportedException();
        public override void SetLength(long value) => throw new NotSupportedException();
        public override void Write(byte[] buffer, int offset, int count) => throw new NotSupportedException();
    }

    private sealed class PrefixThenSuffixStream(byte[] prefix, byte[] suffix, Task release) : Stream
    {
        private int _prefixOffset;
        private int _suffixOffset;

        public override bool CanRead => true;
        public override bool CanSeek => false;
        public override bool CanWrite => false;
        public override long Length => throw new NotSupportedException();
        public override long Position
        {
            get => throw new NotSupportedException();
            set => throw new NotSupportedException();
        }

        public override int Read(byte[] buffer, int offset, int count) =>
            throw new NotSupportedException();

        public override async ValueTask<int> ReadAsync(
            Memory<byte> buffer,
            CancellationToken cancellationToken = default)
        {
            if (_prefixOffset < prefix.Length)
            {
                int count = Math.Min(buffer.Length, prefix.Length - _prefixOffset);
                prefix.AsMemory(_prefixOffset, count).CopyTo(buffer);
                _prefixOffset += count;
                return count;
            }
            await release.WaitAsync(cancellationToken);
            if (_suffixOffset < suffix.Length)
            {
                int count = Math.Min(buffer.Length, suffix.Length - _suffixOffset);
                suffix.AsMemory(_suffixOffset, count).CopyTo(buffer);
                _suffixOffset += count;
                return count;
            }
            await Task.Delay(Timeout.InfiniteTimeSpan, cancellationToken);
            return 0;
        }

        public override void Flush() => throw new NotSupportedException();
        public override long Seek(long offset, SeekOrigin origin) => throw new NotSupportedException();
        public override void SetLength(long value) => throw new NotSupportedException();
        public override void Write(byte[] buffer, int offset, int count) => throw new NotSupportedException();
    }
}
