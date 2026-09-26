using System.Runtime.InteropServices;
using Sidey.Core.Abstractions;
using Sidey.Core.Localization;
using Sidey.Core.Overlay;

namespace Sidey.Platform.Windows.Monitoring;

public sealed record WindowsMonitorInfo(
    string Identifier,
    string Name,
    NativePixelRect MonitorPixels,
    NativePixelRect WorkAreaPixels,
    uint Dpi,
    bool IsPrimary);

public sealed class WindowsMonitorService : IMonitorService
{
    public IReadOnlyList<MonitorGeometry> GetMonitors() => [.. GetAll()
        .Select(monitor =>
        {
            double scale = monitor.Dpi / 96d;
            return new MonitorGeometry(
                monitor.Identifier,
                monitor.Name,
                new RectD(
                    monitor.WorkAreaPixels.X / scale,
                    monitor.WorkAreaPixels.Y / scale,
                    monitor.WorkAreaPixels.Width / scale,
                    monitor.WorkAreaPixels.Height / scale),
                monitor.Dpi,
                monitor.IsPrimary);
        })];

    public static IReadOnlyList<WindowsMonitorInfo> GetAll()
    {
        if (!OperatingSystem.IsWindows())
        {
            throw new PlatformNotSupportedException("Monitor discovery requires Windows.");
        }

        var monitors = new List<WindowsMonitorInfo>();
        NativeMethods.EnumDisplayMonitors(
            nint.Zero,
            nint.Zero,
            (monitor, _, _, _) =>
            {
                var info = new MonitorInfoEx
                {
                    Size = Marshal.SizeOf<MonitorInfoEx>(),
                    DeviceName = string.Empty,
                };
                if (!NativeMethods.GetMonitorInfo(monitor, ref info))
                {
                    return true;
                }

                uint dpi = NativeMethods.GetDpiForMonitor(
                    monitor,
                    MonitorDpiType.Effective,
                    out uint dpiX,
                    out _) == 0
                    ? dpiX
                    : NativeMethods.GetDpiForSystem();
                NativeRect work = info.Work;
                string identifier = string.IsNullOrWhiteSpace(info.DeviceName)
                    ? $"monitor-{monitors.Count + 1}"
                    : info.DeviceName;
                monitors.Add(new WindowsMonitorInfo(
                    identifier,
                    identifier,
                    new NativePixelRect(
                        info.Monitor.Left,
                        info.Monitor.Top,
                        info.Monitor.Right - info.Monitor.Left,
                        info.Monitor.Bottom - info.Monitor.Top),
                    new NativePixelRect(
                        work.Left,
                        work.Top,
                        work.Right - work.Left,
                        work.Bottom - work.Top),
                    dpi,
                    (info.Flags & 1) != 0));
                return true;
            },
            nint.Zero);
        return monitors;
    }

    public static WindowsMonitorInfo Select(string? identifier)
    {
        IReadOnlyList<WindowsMonitorInfo> monitors = GetAll();
        if (monitors.Count == 0)
        {
            throw new InvalidOperationException(I18n.Get("settings.placement.monitor.unavailable"));
        }

        return identifier is not null
            ? monitors.FirstOrDefault(monitor => monitor.Identifier == identifier)
                ?? monitors.FirstOrDefault(monitor => monitor.IsPrimary)
                ?? monitors[0]
            : monitors.FirstOrDefault(monitor => monitor.IsPrimary) ?? monitors[0];
    }

    private delegate bool MonitorEnumerationCallback(
        nint monitor,
        nint deviceContext,
        nint monitorRectangle,
        nint data);

    private enum MonitorDpiType
    {
        Effective = 0,
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct NativeRect
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct MonitorInfoEx
    {
        public int Size;
        public NativeRect Monitor;
        public NativeRect Work;
        public uint Flags;

        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string DeviceName;
    }

    private static class NativeMethods
    {
        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool EnumDisplayMonitors(
            nint deviceContext,
            nint clipRectangle,
            MonitorEnumerationCallback callback,
            nint data);

        [DllImport("user32.dll", EntryPoint = "GetMonitorInfoW", SetLastError = true, CharSet = CharSet.Unicode)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool GetMonitorInfo(nint monitor, ref MonitorInfoEx info);

        [DllImport("shcore.dll")]
        public static extern int GetDpiForMonitor(
            nint monitor,
            MonitorDpiType dpiType,
            out uint dpiX,
            out uint dpiY);

        [DllImport("user32.dll")]
        public static extern uint GetDpiForSystem();
    }
}
