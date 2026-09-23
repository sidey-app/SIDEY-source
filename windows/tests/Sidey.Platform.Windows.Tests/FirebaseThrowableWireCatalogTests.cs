namespace Sidey.Platform.Windows.Tests;

public sealed class FirebaseThrowableWireCatalogTests
{
    [Fact]
    public void FutureThrowableItemsRemainAvailableForForwardCompatibleRendering()
    {
        SupabaseBackendGateway.DatabaseFirebaseWireItem[] rows =
        [
            new("throwable", "throwable_banana", 7),
            new("throwable", "throwable_tennis_ball", 18),
            new("character", "character_pixel_shiba", 19),
            new("throwable", "throwable_without_wire_code", null),
        ];

        IReadOnlyDictionary<string, string> result =
            SupabaseBackendGateway.BuildFirebaseThrowableWireCodes(rows);

        Assert.Equal("7", result["throwable_banana"]);
        Assert.Equal("18", result["throwable_tennis_ball"]);
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
}
