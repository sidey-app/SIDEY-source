using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Sidey.App.Localization;
using Sidey.Core.Localization;
using Sidey.Platform.Windows;
using Sidey.Presentation.Services;
using Sidey.Presentation.ViewModels;

namespace Sidey.App.Views;

public sealed partial class OnboardingWindow : Window
{
    private bool _isClosed;
    private readonly WindowsMinimumSizeController _minimumSizeController;

    public OnboardingWindow(AppCoordinator coordinator)
    {
        InitializeComponent();
        RefreshLocalizationLayout();
        ViewModel = new OnboardingViewModel(coordinator);
        OnboardingRoot.DataContext = ViewModel;
        SideyWindowTheme.Apply(OnboardingRoot, coordinator.State.Preferences.Theme);
        ViewModel.Completed += OnCompleted;
        Closed += OnWindowClosed;
        Title = I18n.Get("settings.window.title");
        AppTitleBar.IconSource = new ImageIconSource
        {
            ImageSource = new Microsoft.UI.Xaml.Media.Imaging.BitmapImage(new Uri(Path.Combine(
                SideyDeploymentPaths.DeploymentRoot(),
                "Assets",
                "Icons",
                "SideyAppIcon-20.png"))),
        };
        LandingIcon.Source = new Microsoft.UI.Xaml.Media.Imaging.BitmapImage(new Uri(Path.Combine(
            SideyDeploymentPaths.DeploymentRoot(),
            "Assets",
            "Icons",
            "SideyAppIcon.png")));
        SideyWindowIcon.Apply(AppWindow);
        if (Microsoft.UI.Windowing.AppWindowTitleBar.IsCustomizationSupported())
        {
            ExtendsContentIntoTitleBar = true;
            SetTitleBar(AppTitleBar);
        }
        SideyWindowTheme.FollowTitleBarTheme(this, OnboardingRoot);
        ApplyBackdrop();
        ResponsiveWindowSize minimumWindowSize = ApplyResponsiveSize();
        _minimumSizeController = new WindowsMinimumSizeController(
            WinRT.Interop.WindowNative.GetWindowHandle(this),
            minimumWindowSize);
        AppWindow.Closing += OnAppWindowClosing;
    }

    public event Action? Completed;

    public OnboardingViewModel ViewModel { get; }

    public void RefreshLocalizationLayout() => LocalizationLayout.Apply(OnboardingRoot);

    public void ApplyState(CoordinatorState state)
    {
        if (!_isClosed)
        {
            SideyWindowTheme.Apply(OnboardingRoot, state.Preferences.Theme);
            ViewModel.ApplyState(state);
        }
    }

    public void ShowError(Exception exception)
    {
        if (!_isClosed)
        {
            GoogleSignInInfoBar.IsOpen = false;
            ViewModel.ReportError(exception);
        }
    }

    public void ShowGoogleSignInComplete()
    {
        if (!_isClosed)
        {
            ViewModel.ErrorMessage = null;
            GoogleSignInInfoBar.IsOpen = true;
        }
    }

    public void ShowAndActivate()
    {
        if (_isClosed)
        {
            return;
        }

        AppWindow.Show();
        Activate();
        SideyWindowActivation.BringToForeground(this);
    }

    private void OnCompleted() => Completed?.Invoke();

    private void OnAppWindowClosing(
        Microsoft.UI.Windowing.AppWindow sender,
        Microsoft.UI.Windowing.AppWindowClosingEventArgs args)
    {
        _ = sender;
        _ = args;
        PrepareForClose();
    }

    private void PrepareForClose()
    {
        if (_isClosed)
        {
            return;
        }

        _isClosed = true;
        OnboardingRoot.DataContext = null;
        ViewModel.Dispose();
    }

    private void ApplyBackdrop()
    {
        SideyWindowTheme.ApplyBackdrop(this, OnboardingFallbackBackground);
    }

    private ResponsiveWindowSize ApplyResponsiveSize()
    {
        WindowsMonitorInfo monitor = WindowsMonitorService.Select(identifier: null);
        ResponsiveWindowSize size = ResponsiveWindowSizePolicy.Calculate(
            monitor,
            SideyWindowKind.Onboarding);
        ResponsiveWindowSize minimumWindowSize = ResponsiveWindowSizePolicy.Minimum(
            monitor,
            SideyWindowKind.Onboarding);
        AppWindow.Resize(new Windows.Graphics.SizeInt32(size.Width, size.Height));
        AppWindow.Move(new Windows.Graphics.PointInt32(
            monitor.WorkAreaPixels.X + ((monitor.WorkAreaPixels.Width - size.Width) / 2),
            monitor.WorkAreaPixels.Y + ((monitor.WorkAreaPixels.Height - size.Height) / 2)));
        return minimumWindowSize;
    }

    private void OnWindowClosed(object sender, WindowEventArgs args)
    {
        _ = sender;
        _ = args;
        PrepareForClose();
        AppWindow.Closing -= OnAppWindowClosing;
        ViewModel.Completed -= OnCompleted;
        _minimumSizeController.Dispose();
    }
}
