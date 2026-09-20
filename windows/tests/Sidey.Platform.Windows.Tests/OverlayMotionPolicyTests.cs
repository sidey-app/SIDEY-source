using Sidey.Overlay;

namespace Sidey.Platform.Windows.Tests;

public sealed class OverlayMotionPolicyTests
{
    [Fact]
    public void EntranceFadesInWhenWindowsAnimationsAreEnabled()
    {
        byte first = LayeredPixelWorldRenderer.EntranceOpacity(0, animationsEnabled: true);
        byte middle = LayeredPixelWorldRenderer.EntranceOpacity(3, animationsEnabled: true);
        byte final = LayeredPixelWorldRenderer.EntranceOpacity(8, animationsEnabled: true);

        Assert.Equal(0, first);
        Assert.InRange(middle, 1, 254);
        Assert.Equal(byte.MaxValue, final);
    }

    [Fact]
    public void EntranceAppearsImmediatelyWhenWindowsAnimationsAreDisabled()
    {
        Assert.Equal(
            byte.MaxValue,
            LayeredPixelWorldRenderer.EntranceOpacity(0, animationsEnabled: false));
    }

    [Fact]
    public void ExitFadesOutWhenWindowsAnimationsAreEnabled()
    {
        byte first = LayeredPixelWorldRenderer.ExitOpacity(0, animationsEnabled: true);
        byte middle = LayeredPixelWorldRenderer.ExitOpacity(4, animationsEnabled: true);
        byte final = LayeredPixelWorldRenderer.ExitOpacity(8, animationsEnabled: true);

        Assert.Equal(byte.MaxValue, first);
        Assert.InRange(middle, (byte)1, (byte)254);
        Assert.Equal(0, final);
        Assert.True(first > middle);
        Assert.True(middle > final);
    }

    [Fact]
    public void ExitDisappearsImmediatelyWhenWindowsAnimationsAreDisabled()
    {
        Assert.Equal(
            0,
            LayeredPixelWorldRenderer.ExitOpacity(0, animationsEnabled: false));
    }

    [Fact]
    public void TaskbarInsetSnapsWhenWindowsAnimationsAreDisabled()
    {
        Assert.Equal(
            48d,
            LayeredPixelWorldRenderer.NextEdgeInset(
                current: 0d,
                target: 48,
                integerScale: 2,
                animationsEnabled: false));
    }

    [Fact]
    public void TaskbarInsetMovesGraduallyWhenWindowsAnimationsAreEnabled()
    {
        double next = LayeredPixelWorldRenderer.NextEdgeInset(
            current: 0d,
            target: 48,
            integerScale: 2,
            animationsEnabled: true);

        Assert.InRange(next, 0.01d, 47.99d);
    }
}
