using Sidey.Core.Domain;

namespace Sidey.Core.Tests;

public sealed class ComposerPlacementPolicyTests
{
    [Fact]
    public void MissingPlacementUsesTopCenter()
    {
        ComposerPlacement result = ComposerPlacementPolicy.Resolve(null, "primary", 1920, 1040, 400, 56);

        Assert.Equal(new ComposerPlacement("primary", 760, 10), result);
    }

    [Fact]
    public void SavedLogicalPositionSurvivesMonitorOriginAndDpiChanges()
    {
        var saved = new ComposerPlacement("secondary", 125, 250);

        // Work area and window dimensions are converted to DIP before restoration.
        foreach (double scale in new[] { 1, 1.25, 1.5, 2 })
        {
            ComposerPlacement result = ComposerPlacementPolicy.Resolve(
                saved, "secondary", 1920 / scale, 1040 / scale, 400, 56);

            Assert.Equal(saved, result);
        }
    }

    [Fact]
    public void RemovedMonitorPlacementIsClampedToFallbackWorkArea()
    {
        var saved = new ComposerPlacement("removed", 1700, 900);

        ComposerPlacement result = ComposerPlacementPolicy.Resolve(saved, "primary", 1280, 720, 400, 56);

        Assert.Equal(new ComposerPlacement("primary", 880, 664), result);
    }

    [Theory]
    [InlineData(-50, -10, 0, 0)]
    [InlineData(double.MaxValue, double.MaxValue, 880, 664)]
    public void WindowRemainsInsideWorkArea(double x, double y, double expectedX, double expectedY)
    {
        ComposerPlacement result = ComposerPlacementPolicy.Resolve(
            new ComposerPlacement("primary", x, y), "primary", 1280, 720, 400, 56);

        Assert.Equal(new ComposerPlacement("primary", expectedX, expectedY), result);
    }

    [Fact]
    public void SmallerWorkAreaKeepsDragGripAtWorkAreaOrigin()
    {
        ComposerPlacement result = ComposerPlacementPolicy.Resolve(
            new ComposerPlacement("primary", 500, 500), "primary", 320, 40, 400, 56);

        Assert.Equal(new ComposerPlacement("primary", 0, 0), result);
    }

    [Theory]
    [InlineData("", 1, 2)]
    [InlineData(" ", 1, 2)]
    [InlineData("primary", double.NaN, 2)]
    [InlineData("primary", 1, double.PositiveInfinity)]
    public void InvalidPlacementUsesDefault(string monitor, double x, double y)
    {
        ComposerPlacement result = ComposerPlacementPolicy.Resolve(
            new ComposerPlacement(monitor, x, y), "primary", 1920, 1040, 400, 56);

        Assert.Equal(new ComposerPlacement("primary", 760, 10), result);
    }
}
