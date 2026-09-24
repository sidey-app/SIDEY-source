using System.Net;
using System.Reflection;
using System.Runtime.CompilerServices;
using System.Text.Json;
using Sidey.Core.Abstractions;
using Sidey.Core.Domain;
using Sidey.Infrastructure.Authentication;
using Sidey.Infrastructure.Realtime;

namespace Sidey.Platform.Windows.Tests;

public sealed class FirebaseThrowableWireCatalogTests
{
    [Fact]
    public void FutureThrowableItemsRemainAvailableForForwardCompatibleRendering()
    {
        const string FutureThrowableId = "throwable_future_test";
        SupabaseBackendGateway.DatabaseFirebaseWireItem[] rows =
        [
            new("throwable", "throwable_banana", 7),
            new("throwable", FutureThrowableId, 18),
            new("character", "character_pixel_shiba", 19),
            new("throwable", "throwable_without_wire_code", null),
        ];

        IReadOnlyDictionary<string, string> result =
            SupabaseBackendGateway.BuildFirebaseThrowableWireCodes(rows);

        Assert.DoesNotContain(FutureThrowableId, CosmeticCatalog.ThrowableIds);
        Assert.Equal("7", result["throwable_banana"]);
        Assert.Equal("18", result[FutureThrowableId]);
        Assert.Equal("patch_soft_ball", CosmeticCatalog.ResolveThrowableAssetId(FutureThrowableId));
        Assert.Equal(2, result.Count);
    }

    [Theory]
    [InlineData("", 1)]
    [InlineData("   ", 1)]
    [InlineData("throwable_future", 0)]
    [InlineData("throwable_future", 1_000_000)]
    public void InvalidServerWireItemsStillFailClosed(string catalogItemId, int wireCode)
    {
        SupabaseBackendGateway.DatabaseFirebaseWireItem[] rows =
        [
            new("throwable", catalogItemId, wireCode),
        ];

        Assert.Throws<InvalidDataException>(
            () => SupabaseBackendGateway.BuildFirebaseThrowableWireCodes(rows));
    }

    [Fact]
    public void DuplicateFutureWireCodesStillFailClosed()
    {
        SupabaseBackendGateway.DatabaseFirebaseWireItem[] rows =
        [
            new("throwable", "throwable_future_one", 18),
            new("throwable", "throwable_future_two", 18),
        ];

        Assert.Throws<InvalidDataException>(
            () => SupabaseBackendGateway.BuildFirebaseThrowableWireCodes(rows));
    }

    [Fact]
    public async Task WireCatalogFailureDoesNotBlockLegacyRealtimeSynchronization()
    {
        var realtime = new LegacySelectionTransport();
        var handler = new FailingWireCatalogHandler(realtime);
        using var httpClient = new HttpClient(handler);
        var configuration = new SupabaseRuntimeConfiguration(
            new Uri("https://wire-catalog.example.invalid"), "test-key");
        ICredentialStore credentials = DispatchProxy.Create<ICredentialStore, SessionCredentials>();
        using var auth = new SupabaseAnonymousAuthService(configuration, credentials, httpClient);
        await using var gateway = new SupabaseBackendGateway(
            configuration, auth, credentials, httpClient, realtime);

        await gateway.SynchronizeRealtimeRoomsAsync(
            new Dictionary<Guid, long>(), null, PresenceState.Online);

        Assert.True(realtime.Synchronized);
        Assert.False(realtime.WireCodesConfigured);
        Assert.Equal(1, handler.RequestCount);
    }

    private sealed class LegacySelectionTransport : IRealtimeTransport
    {
        public bool Synchronized { get; private set; }
        public bool WireCodesConfigured { get; private set; }
        public RealtimeConnectionStatus ConnectionStatus => new(true, true, true);
        public bool IsRecoveryPaused => false;
        public bool RequiresThrowableWireCodes => true;

        public async IAsyncEnumerable<BackendEvent> ReadEventsAsync(
            [EnumeratorCancellation] CancellationToken cancellationToken)
        {
            await Task.CompletedTask;
            yield break;
        }

        public Task SynchronizeAsync(
            IReadOnlyDictionary<Guid, long> roomEpochs,
            Guid? activeRoomId,
            PresenceState localPresence,
            CancellationToken cancellationToken)
        {
            Synchronized = true;
            return Task.CompletedTask;
        }

        public void ConfigureThrowableWireCodes(IReadOnlyDictionary<string, string> wireCodesByCatalogItemId) =>
            WireCodesConfigured = true;

        public Task PublishPresenceAsync(
            Guid roomId, PresenceState state, CancellationToken cancellationToken) => Task.CompletedTask;

        public async Task<bool> RunWhileConnectedAsync(
            Func<CancellationToken, Task> operation, CancellationToken cancellationToken)
        {
            await operation(cancellationToken);
            return true;
        }

        public void RequestReconnect(bool userInitiated = false)
        {
        }

        public ValueTask DisposeAsync() => ValueTask.CompletedTask;
    }

    private sealed class FailingWireCatalogHandler(LegacySelectionTransport realtime) : HttpMessageHandler
    {
        public int RequestCount { get; private set; }

        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request, CancellationToken cancellationToken)
        {
            Assert.True(realtime.Synchronized);
            Assert.Equal("/rest/v1/rpc/get_store_state_v2", request.RequestUri?.AbsolutePath);
            RequestCount++;
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.ServiceUnavailable));
        }
    }

    public class SessionCredentials : DispatchProxy
    {
        protected override object? Invoke(MethodInfo? targetMethod, object?[]? args)
        {
            Assert.Equal(nameof(ICredentialStore.ReadAsync), targetMethod?.Name);
            Assert.Equal(CredentialKey.SupabaseSession, args![0]);
            return new ValueTask<string?>(JsonSerializer.Serialize(
                new StoredSupabaseSession(
                    "test-token", "test-refresh",
                    Guid.Parse("00000000-0000-0000-0000-000000000042"), DateTimeOffset.MaxValue),
                new JsonSerializerOptions(JsonSerializerDefaults.Web)));
        }
    }
}
