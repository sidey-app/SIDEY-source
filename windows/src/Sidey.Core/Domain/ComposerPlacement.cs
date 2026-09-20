namespace Sidey.Core.Domain;

// Coordinates are logical pixels relative to the selected monitor's work area.
public sealed record ComposerPlacement(string MonitorIdentifier, double X, double Y)
{
    public ComposerPlacement? Normalize() =>
        string.IsNullOrWhiteSpace(MonitorIdentifier) || !double.IsFinite(X) || !double.IsFinite(Y)
            ? null
            : this;
}

public static class ComposerPlacementPolicy
{
    public static ComposerPlacement Resolve(
        ComposerPlacement? saved,
        string monitorIdentifier,
        double workAreaWidth,
        double workAreaHeight,
        double windowWidth,
        double windowHeight)
    {
        saved = saved?.Normalize();
        double maximumX = Math.Max(0, workAreaWidth - windowWidth);
        double maximumY = Math.Max(0, workAreaHeight - windowHeight);
        return new ComposerPlacement(
            monitorIdentifier,
            Math.Clamp(saved?.X ?? (maximumX / 2), 0, maximumX),
            Math.Clamp(saved?.Y ?? 10, 0, maximumY));
    }
}
