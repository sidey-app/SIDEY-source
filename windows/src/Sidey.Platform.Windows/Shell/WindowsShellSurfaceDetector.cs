using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

namespace Sidey.Platform.Windows.Shell;

public readonly record struct WindowsShellYieldSurface(nint Window, bool OverlayAboveWindow);

public static class WindowsShellSurfaceDetector
{
    private static readonly WindowsShellSurfaceResolver s_resolver = new(
        VisibleSurface,
        ForegroundRoot,
        IsShellSurface,
        CanCoverOverlay,
        IsFullscreenCaptureSurface);

    public static nint ForegroundSurface(NativePixelRect monitorBounds)
    {
        if (!OperatingSystem.IsWindows())
        {
            return nint.Zero;
        }

        return s_resolver.ForegroundSurface(monitorBounds);
    }

    public static WindowsShellYieldSurface YieldSurface(
        NativePixelRect monitorBounds,
        nint revealedAutoHideTaskbar,
        nint overlayWindow)
    {
        nint shellSurface = ForegroundSurface(monitorBounds);
        if (revealedAutoHideTaskbar == nint.Zero && shellSurface == nint.Zero)
        {
            return default;
        }

        int expectedWindowCount = 1
            + (revealedAutoHideTaskbar != nint.Zero ? 1 : 0)
            + (shellSurface != nint.Zero && shellSurface != revealedAutoHideTaskbar ? 1 : 0);
        var windowsInZOrder = new List<nint>(expectedWindowCount);
        _ = NativeMethods.EnumWindows((window, _) =>
        {
            if ((window == revealedAutoHideTaskbar
                    || window == shellSurface
                    || window == overlayWindow)
                && NativeMethods.IsWindowVisible(window))
            {
                windowsInZOrder.Add(window);
            }

            return windowsInZOrder.Count < expectedWindowCount;
        }, nint.Zero);

        nint yieldBehind = WindowsShellSurfacePolicy.BackmostSurface(
            revealedAutoHideTaskbar,
            shellSurface,
            windowsInZOrder);
        return new WindowsShellYieldSurface(
            yieldBehind,
            WindowsShellSurfacePolicy.IsWindowAbove(
                overlayWindow,
                yieldBehind,
                windowsInZOrder));
    }

    private static nint VisibleSurface(NativePixelRect monitorBounds)
    {
        nint surface = nint.Zero;
        _ = NativeMethods.EnumWindows((window, _) =>
        {
            if (!NativeMethods.IsWindowVisible(window))
            {
                return true;
            }

            var className = new StringBuilder(256);
            _ = NativeMethods.GetClassName(window, className, className.Capacity);
            string windowClass = className.ToString();
            nint style = NativeMethods.GetWindowLongPtr(window, -16);
            nint extendedStyle = NativeMethods.GetWindowLongPtr(window, -20);
            if (IsFullscreenCaptureSurface(window, extendedStyle, monitorBounds)
                && CanCoverOverlay(window, monitorBounds))
            {
                surface = window;
                return false;
            }

            if (!WindowsShellSurfacePolicy.IsTransientPopup(
                    windowClass,
                    style,
                    extendedStyle)
                || !CanCoverOverlay(window, monitorBounds))
            {
                return true;
            }

            if (!WindowsShellSurfacePolicy.ShouldYieldTransientSurface(
                    ProcessName(window),
                    windowClass,
                    style,
                    extendedStyle))
            {
                return true;
            }

            surface = window;
            return false;
        }, nint.Zero);
        return surface;
    }

    private static bool CanCoverOverlay(nint window, NativePixelRect monitorBounds)
    {
        if (!NativeMethods.IsWindowVisible(window))
        {
            return false;
        }

        if (!NativeMethods.GetWindowRect(window, out NativeMethods.Rect bounds))
        {
            return false;
        }

        const uint DwmwaCloaked = 14;
        int cloakReasons = 0;
        int result = NativeMethods.DwmGetWindowAttribute(
            window,
            DwmwaCloaked,
            out cloakReasons,
            sizeof(int));
        if (result < 0)
        {
            return false;
        }

        return WindowsShellSurfacePolicy.CanCoverOverlay(
            isVisible: true,
            isCloaked: cloakReasons != 0,
            (long)bounds._right - bounds._left,
            (long)bounds._bottom - bounds._top)
            && WindowsShellSurfacePolicy.IntersectsMonitor(
                bounds._left, bounds._top, bounds._right, bounds._bottom, monitorBounds);
    }

    private static bool IsFullscreenCaptureSurface(nint window, NativePixelRect monitorBounds)
    {
        return IsFullscreenCaptureSurface(
            window,
            NativeMethods.GetWindowLongPtr(window, -20),
            monitorBounds);
    }

    private static bool IsFullscreenCaptureSurface(
        nint window,
        nint extendedStyle,
        NativePixelRect monitorBounds)
    {
        const long TopmostStyle = 0x00000008L;
        if ((extendedStyle.ToInt64() & TopmostStyle) == 0)
        {
            return false;
        }

        if (!NativeMethods.GetWindowRect(window, out NativeMethods.Rect bounds))
        {
            return false;
        }

        return WindowsShellSurfacePolicy.IsFullscreenCaptureSurface(
            ProcessName(window),
            extendedStyle,
            bounds._left,
            bounds._top,
            bounds._right,
            bounds._bottom,
            monitorBounds);
    }

    private static nint ForegroundRoot()
    {
        nint foreground = NativeMethods.GetForegroundWindow();
        if (foreground == nint.Zero)
        {
            return nint.Zero;
        }

        nint root = NativeMethods.GetAncestor(foreground, 2);
        return root != nint.Zero ? root : foreground;
    }

    private static bool IsShellSurface(nint window)
    {
        string? processName = ProcessName(window);
        if (processName is null)
        {
            return false;
        }

        var className = new StringBuilder(256);
        _ = NativeMethods.GetClassName(window, className, className.Capacity);
        return WindowsShellSurfacePolicy.ShouldYield(processName, className.ToString());
    }

    private static string? ProcessName(nint window)
    {
        _ = NativeMethods.GetWindowThreadProcessId(window, out uint processId);
        if (processId == 0)
        {
            return null;
        }

        try
        {
            using var process = Process.GetProcessById((int)processId);
            return process.ProcessName;
        }
        catch (ArgumentException)
        {
            return null;
        }
        catch (InvalidOperationException)
        {
            return null;
        }
        catch (System.ComponentModel.Win32Exception)
        {
            return null;
        }
    }

    private static class NativeMethods
    {
        [DllImport("user32.dll")]
        internal static extern nint GetForegroundWindow();

        [DllImport("user32.dll")]
        internal static extern nint GetAncestor(nint window, uint flags);

        [DllImport("user32.dll")]
        internal static extern uint GetWindowThreadProcessId(nint window, out uint processId);

        [DllImport("user32.dll", EntryPoint = "GetClassNameW", CharSet = CharSet.Unicode)]
        internal static extern int GetClassName(nint window, StringBuilder className, int maximumCount);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool EnumWindows(EnumWindowsCallback callback, nint parameter);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool IsWindowVisible(nint window);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool GetWindowRect(nint window, out Rect bounds);

        [DllImport("dwmapi.dll")]
        internal static extern int DwmGetWindowAttribute(
            nint window,
            uint attribute,
            out int attributeValue,
            uint attributeSize);

        [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")]
        internal static extern nint GetWindowLongPtr(nint window, int index);

        internal delegate bool EnumWindowsCallback(nint window, nint parameter);

        [StructLayout(LayoutKind.Sequential)]
        internal struct Rect
        {
            internal int _left;
            internal int _top;
            internal int _right;
            internal int _bottom;
        }
    }
}

internal sealed class WindowsShellSurfaceResolver(
    Func<NativePixelRect, nint> visibleSurface,
    Func<nint> foregroundRoot,
    Func<nint, bool> shouldYield,
    Func<nint, NativePixelRect, bool>? canCoverOverlay = null,
    Func<nint, NativePixelRect, bool>? isFullscreenCaptureSurface = null)
{
    private readonly Lock _cacheGate = new();
    private nint _cachedWindow;
    private bool _cachedShouldYield;

    internal nint ForegroundSurface(NativePixelRect monitorBounds = default)
    {
        nint transientPopup = visibleSurface(monitorBounds);
        if (transientPopup != nint.Zero)
        {
            return transientPopup;
        }

        nint foreground = foregroundRoot();
        if (foreground == nint.Zero
            || (canCoverOverlay is not null && !canCoverOverlay(foreground, monitorBounds)))
        {
            return nint.Zero;
        }

        // Window styles and bounds can change while the foreground HWND stays the same.
        if (isFullscreenCaptureSurface?.Invoke(foreground, monitorBounds) == true)
        {
            return foreground;
        }

        lock (_cacheGate)
        {
            if (foreground == _cachedWindow)
            {
                return _cachedShouldYield ? foreground : nint.Zero;
            }

            _cachedWindow = foreground;
            _cachedShouldYield = shouldYield(foreground);
            return _cachedShouldYield ? foreground : nint.Zero;
        }
    }
}

public static class WindowsShellSurfacePolicy
{
    private static readonly HashSet<string> s_captureHosts = new(StringComparer.OrdinalIgnoreCase)
    {
        "ScreenClippingHost",
        "SnippingTool",
    };

    private static readonly HashSet<string> s_shellProcesses = new(StringComparer.OrdinalIgnoreCase)
    {
        "SearchApp",
        "SearchHost",
        "SearchUI",
        "ShellExperienceHost",
        "ShellHost",
        "StartMenuExperienceHost",
        "TextInputHost",
        "MicrosoftStartFeedProvider",
        "WidgetBoard",
        "Widgets",
        "WidgetsBoard",
        "WidgetService",
    };

    internal static nint BackmostSurface(
        nint taskbarWindow,
        nint shellWindow,
        IReadOnlyList<nint> windowsInZOrder)
    {
        nint backmost = nint.Zero;
        foreach (nint window in windowsInZOrder)
        {
            if (window == taskbarWindow || window == shellWindow)
            {
                backmost = window;
            }
        }

        return backmost;
    }

    internal static bool IsWindowAbove(
        nint overlayWindow,
        nint surfaceWindow,
        IReadOnlyList<nint> windowsInZOrder)
    {
        if (overlayWindow == nint.Zero || surfaceWindow == nint.Zero)
        {
            return false;
        }

        bool overlaySeen = false;
        foreach (nint window in windowsInZOrder)
        {
            if (window == surfaceWindow)
            {
                return overlaySeen;
            }

            if (window == overlayWindow)
            {
                overlaySeen = true;
            }
        }

        return false;
    }

    public static bool ShouldYield(string? processName, string? windowClass)
    {
        if (string.IsNullOrWhiteSpace(processName))
        {
            return false;
        }

        if (s_shellProcesses.Contains(processName))
        {
            return true;
        }

        return StringComparer.OrdinalIgnoreCase.Equals(processName, "explorer")
            && IsExplorerTaskbarSurface(windowClass);
    }

    internal static bool IntersectsMonitor(
        long left, long top, long right, long bottom, NativePixelRect monitorBounds) =>
        monitorBounds.IsValid && right > left && bottom > top
        && left < (long)monitorBounds.X + monitorBounds.Width
        && right > monitorBounds.X
        && top < (long)monitorBounds.Y + monitorBounds.Height
        && bottom > monitorBounds.Y;

    internal static bool CanCoverOverlay(
        bool isVisible,
        bool isCloaked,
        long width,
        long height) =>
        isVisible && !isCloaked && width > 0 && height > 0;

    internal static bool IsFullscreenTopmostSurface(
        nint extendedStyle,
        long left,
        long top,
        long right,
        long bottom,
        NativePixelRect monitorBounds)
    {
        const long TopmostStyle = 0x00000008L;
        return (extendedStyle.ToInt64() & TopmostStyle) != 0
            && monitorBounds.IsValid
            && right > left
            && bottom > top
            && left <= monitorBounds.X
            && top <= monitorBounds.Y
            && right >= (long)monitorBounds.X + monitorBounds.Width
            && bottom >= (long)monitorBounds.Y + monitorBounds.Height;
    }

    internal static bool IsCaptureHost(string? processName) =>
        processName is not null && s_captureHosts.Contains(processName);

    internal static bool IsFullscreenCaptureSurface(
        string? processName,
        nint extendedStyle,
        long left,
        long top,
        long right,
        long bottom,
        NativePixelRect monitorBounds) =>
        IsCaptureHost(processName)
        && IsFullscreenTopmostSurface(
            extendedStyle, left, top, right, bottom, monitorBounds);

    internal static bool ShouldYieldTransientSurface(
        string? processName,
        string? windowClass,
        nint style = default,
        nint extendedStyle = default)
    {
        if (!IsTransientPopup(windowClass, style, extendedStyle)
            || string.IsNullOrWhiteSpace(processName))
        {
            return false;
        }

        return s_shellProcesses.Contains(processName)
            || StringComparer.OrdinalIgnoreCase.Equals(processName, "explorer");
    }

    public static bool IsTaskbarWindow(string? windowClass) =>
        StringComparer.OrdinalIgnoreCase.Equals(windowClass, "Shell_TrayWnd")
        || StringComparer.OrdinalIgnoreCase.Equals(windowClass, "Shell_SecondaryTrayWnd");

    public static bool IsTransientPopup(
        string? windowClass,
        nint style = default,
        nint extendedStyle = default)
    {
        if (string.IsNullOrWhiteSpace(windowClass))
        {
            return false;
        }

        if (IsPersistentShellWindow(windowClass)
            || StringComparer.OrdinalIgnoreCase.Equals(windowClass, "SIDEY.NativeOverlayWindow"))
        {
            return false;
        }

        bool recognizedClass = StringComparer.OrdinalIgnoreCase.Equals(windowClass, "#32768")
            || StringComparer.OrdinalIgnoreCase.Equals(windowClass, "Xaml_WindowedPopupClass")
            || StringComparer.OrdinalIgnoreCase.Equals(windowClass, "tooltips_class32")
            || windowClass.Contains("PopupWindowSiteBridge", StringComparison.OrdinalIgnoreCase);
        const long PopupStyle = 0x80000000L;
        const long ToolWindowStyle = 0x00000080L;
        bool transientWindowStyles = (style.ToInt64() & PopupStyle) != 0
            && (extendedStyle.ToInt64() & ToolWindowStyle) != 0;
        return recognizedClass || transientWindowStyles;
    }

    private static bool IsPersistentShellWindow(string windowClass) =>
        StringComparer.OrdinalIgnoreCase.Equals(windowClass, "Progman")
        || StringComparer.OrdinalIgnoreCase.Equals(windowClass, "WorkerW")
        || IsTaskbarWindow(windowClass);

    private static bool IsExplorerTaskbarSurface(string? windowClass)
    {
        if (string.IsNullOrWhiteSpace(windowClass))
        {
            return false;
        }

        return windowClass.Contains("ControlCenter", StringComparison.OrdinalIgnoreCase)
            || windowClass.Contains("MultitaskingView", StringComparison.OrdinalIgnoreCase)
            || windowClass.Contains("NotifyIconOverflow", StringComparison.OrdinalIgnoreCase)
            || windowClass.Contains("OverflowXamlIsland", StringComparison.OrdinalIgnoreCase)
            || windowClass.Contains("XamlExplorerHostIsland", StringComparison.OrdinalIgnoreCase)
            || IsTaskbarWindow(windowClass);
    }
}
