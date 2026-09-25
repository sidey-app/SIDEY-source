using Sidey.Infrastructure.Realtime;

namespace Sidey.Platform.Windows.Tests;

public sealed class FirebaseRealtimeServerClockTests
{
    [Fact]
    public void ServerTimeKeepsAdvancingWhenComputerWallClockIsCorrected()
    {
        var time = new JumpingWallClockTimeProvider();
        DateTimeOffset serverDate = time.GetUtcNow().AddSeconds(14);
        var clock = new FirebaseRealtimeServerClock(time, serverDate);

        time.Advance(TimeSpan.FromSeconds(2));
        time.CorrectWallClock(TimeSpan.FromSeconds(14));

        Assert.Equal(serverDate.AddSeconds(2).ToUnixTimeMilliseconds(), clock.NowMilliseconds());
        Assert.Equal(14_000, clock.OffsetMilliseconds);
    }

    private sealed class JumpingWallClockTimeProvider : TimeProvider
    {
        private long _elapsedTicks;
        private long _wallClockCorrectionTicks;

        public override long TimestampFrequency => TimeSpan.TicksPerSecond;
        public override long GetTimestamp() => _elapsedTicks;
        public override DateTimeOffset GetUtcNow() =>
            DateTimeOffset.FromUnixTimeMilliseconds(1_750_000_000_000)
                .AddTicks(_elapsedTicks + _wallClockCorrectionTicks);

        public void Advance(TimeSpan elapsed) => _elapsedTicks += elapsed.Ticks;
        public void CorrectWallClock(TimeSpan correction) =>
            _wallClockCorrectionTicks += correction.Ticks;
    }
}
