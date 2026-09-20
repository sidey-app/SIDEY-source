using Sidey.Core.Domain;

namespace Sidey.Core.Tests;

public sealed class QuietModeProjectionTests
{
    [Fact]
    public void QuietModeHidesOwnAndRemoteTypingWithoutChangingLiveState()
    {
        var room = Guid.NewGuid();
        PixelWorldMember self = new(Guid.NewGuid(), "self", "pixel_cat", PresenceState.Online, true, true);
        PixelWorldMember other = new(Guid.NewGuid(), "friend", "pixel_cat", PresenceState.Away, true, false);
        WorldSnapshot live = new(room, [self, other], [], [], [], OverlayEdge.Bottom, 10);

        WorldSnapshot quiet = QuietModeProjection.Apply(live, true);

        Assert.All(quiet.Members, member => Assert.False(member.IsTyping));
        Assert.Equal(live.Members.Select(member => member.Presence), quiet.Members.Select(member => member.Presence));
        Assert.Equal(room, quiet.RoomId);
        Assert.All(live.Members, member => Assert.True(member.IsTyping));
        Assert.Same(live, QuietModeProjection.Apply(live, false));
        WorldSnapshot expired = live with { Members = [self with { IsTyping = false }, other with { IsTyping = false }] };
        Assert.All(QuietModeProjection.Apply(expired, false).Members, member => Assert.False(member.IsTyping));
    }
}
