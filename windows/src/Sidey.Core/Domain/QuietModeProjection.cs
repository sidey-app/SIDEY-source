namespace Sidey.Core.Domain;

public static class QuietModeProjection
{
    public static WorldSnapshot Apply(WorldSnapshot snapshot, bool quietMode) => quietMode
        ? snapshot with
        {
            Members = [.. snapshot.Members.Select(member => member with { IsTyping = false })],
            Bubbles = [],
        }
        : snapshot;
}
