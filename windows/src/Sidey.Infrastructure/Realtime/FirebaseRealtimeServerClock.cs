namespace Sidey.Infrastructure.Realtime;

internal sealed class FirebaseRealtimeServerClock
{
    private readonly TimeProvider _timeProvider;
    private readonly long _sampleTimestamp;
    private readonly long _serverMilliseconds;

    public FirebaseRealtimeServerClock(TimeProvider timeProvider, DateTimeOffset serverDate)
    {
        _timeProvider = timeProvider ?? throw new ArgumentNullException(nameof(timeProvider));
        _sampleTimestamp = timeProvider.GetTimestamp();
        _serverMilliseconds = serverDate.ToUnixTimeMilliseconds();
        OffsetMilliseconds = checked(
            _serverMilliseconds - timeProvider.GetUtcNow().ToUnixTimeMilliseconds());
    }

    public long OffsetMilliseconds { get; }

    public long NowMilliseconds() => checked(
        _serverMilliseconds + (long)_timeProvider.GetElapsedTime(_sampleTimestamp).TotalMilliseconds);
}
