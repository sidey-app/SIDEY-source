using System.Runtime.InteropServices;

namespace Sidey.Platform.Windows.Tests;

public sealed class NativeLeftClickTests
{
    [Fact]
    public void OwnCharacterSingleClickOpensComposerOnceAfterTheDoubleClickInterval()
    {
        using var opened = new ManualResetEventSlim();
        int singles = 0;
        int doubles = 0;
        using NativeOverlayWindowThread windows = Create(() =>
        {
            Interlocked.Increment(ref singles);
            opened.Set();
        }, () => Interlocked.Increment(ref doubles));

        Send(windows.HotspotWindowHandle, 0x0201, 0x0202);

        Assert.Equal(0, Volatile.Read(ref singles));
        Assert.True(opened.Wait(ClickTimeout));
        Assert.Equal(1, Volatile.Read(ref singles));
        Assert.Equal(0, Volatile.Read(ref doubles));
    }

    [Fact]
    public void OwnCharacterDoubleClickKeepsComposerClosedAndTheFollowingSingleClickStillWorks()
    {
        using var opened = new ManualResetEventSlim();
        int singles = 0;
        int doubles = 0;
        using NativeOverlayWindowThread windows = Create(() =>
        {
            Interlocked.Increment(ref singles);
            opened.Set();
        }, () => Interlocked.Increment(ref doubles));

        // Windows replaces the second DOWN with DBLCLK, then sends its final UP.
        Send(windows.HotspotWindowHandle, 0x0201, 0x0202, 0x0203, 0x0202);

        Assert.Equal(1, Volatile.Read(ref doubles));
        Assert.False(opened.Wait(CancelledClickObservation));
        Assert.Equal(0, Volatile.Read(ref singles));

        Send(windows.HotspotWindowHandle, 0x0201, 0x0202);
        Assert.True(opened.Wait(ClickTimeout));
        Assert.Equal(1, Volatile.Read(ref singles));
    }

    [Fact]
    public void HidingTheCharacterCancelsItsPendingComposerRequest()
    {
        using var opened = new ManualResetEventSlim();
        using NativeOverlayWindowThread windows = Create(opened.Set, () => { });

        Send(windows.HotspotWindowHandle, 0x0201, 0x0202);
        windows.SetVisible(false);

        Assert.False(opened.Wait(CancelledClickObservation));
        windows.SetVisible(true);
        Send(windows.HotspotWindowHandle, 0x0201, 0x0202);
        Assert.True(opened.Wait(ClickTimeout));
    }

    [Fact]
    public void AHotspotWithoutADoubleClickActionStillActivatesImmediatelyOnRelease()
    {
        int singles = 0;
        using NativeOverlayWindowThread windows = Create(() => Interlocked.Increment(ref singles));

        Send(windows.HotspotWindowHandle, 0x0201, 0x0202);

        Assert.Equal(1, Volatile.Read(ref singles));
    }

    // Timing is the contract: allow one extra second beyond the OS preference
    // to observe a cancelled timer, and two seconds for a live callback.
    private static TimeSpan CancelledClickObservation =>
        TimeSpan.FromSeconds(NativeOverlayWindow.DoubleClickIntervalSeconds + 1);

    private static TimeSpan ClickTimeout =>
        TimeSpan.FromSeconds(NativeOverlayWindow.DoubleClickIntervalSeconds + 2);

    private static NativeOverlayWindowThread Create(Action single, Action? doubleClick = null) =>
        NativeOverlayWindowThread.Start(
            new NativePixelRect(-10000, -10000, 1, 1),
            new NativePixelRect(-10000, -10000, 1, 1),
            hotspotActivated: single,
            hotspotDoubleClicked: doubleClick);

    private static void Send(nint window, params uint[] messages)
    {
        foreach (uint message in messages)
        {
            Assert.NotEqual(nint.Zero, SendMessageTimeout(window, message, 0, 0, 2, 1000, out _));
        }
    }

    [DllImport("user32.dll", EntryPoint = "SendMessageTimeoutW", SetLastError = true)]
    private static extern nint SendMessageTimeout(nint window, uint message, nuint wParam,
        nint lParam, uint flags, uint timeoutMilliseconds, out nuint result);
}
