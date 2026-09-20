using Microsoft.UI.Input;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Sidey.Core.Domain;
using Sidey.Core.Localization;
using Sidey.Platform.Windows;
using Sidey.Presentation.Services;
using Sidey.Presentation.ViewModels;
using Windows.System;

namespace Sidey.App.Views;

public sealed partial class HistoryWindow : Window
{
    private readonly CoordinatorState _initialState;
    private bool _isClosed;
    private bool _isComposing;
    private bool _focusRequested;
    private int _focusGeneration;

    public HistoryWindow(HistoryWindowViewModel viewModel)
    {
        ViewModel = viewModel ?? throw new ArgumentNullException(nameof(viewModel));
        _initialState = viewModel.CurrentState;
        InitializeComponent();
        HistoryRoot.DataContext = ViewModel;
        HistoryInput.TextCompositionStarted += (_, _) => _isComposing = true;
        HistoryInput.TextCompositionEnded += (_, _) => _isComposing = false;
        HistoryInput.Loaded += OnMessageInputLoaded;
        Activated += OnWindowActivated;
        ApplyTheme(_initialState.Preferences.Theme);
        SideyWindowTheme.FollowTitleBarTheme(this, HistoryRoot);
        Title = I18n.Get("window.historyTitle");
        SideyWindowIcon.Apply(AppWindow);
        ApplyResponsiveSize();
        ApplyBackdrop();
        AppWindow.Closing += OnAppWindowClosing;
        Closed += OnWindowClosed;
    }

    public HistoryWindowViewModel ViewModel { get; }

    public void ApplyState(CoordinatorState state)
    {
        if (!_isClosed)
        {
            ApplyTheme(state.Preferences.Theme);
            ViewModel.ApplyState(state);
        }
    }

    public void ApplyTheme(AppThemePreference theme)
    {
        if (!_isClosed)
        {
            SideyWindowTheme.Apply(HistoryRoot, theme);
        }
    }

    public void ShowAndActivate()
    {
        if (_isClosed)
        {
            return;
        }

        _focusRequested = true;
        AppWindow.Show();
        Activate();
        SideyWindowActivation.BringToForeground(this);
        _ = ViewModel.ActivateAsync();
        ViewModel.Composer.OnShown();
        RequestMessageInputFocus();
    }

    private void OnWindowActivated(object sender, WindowActivatedEventArgs args)
    {
        if (args.WindowActivationState == WindowActivationState.Deactivated)
        {
            _focusRequested = false;
            _focusGeneration++;
            ViewModel.Composer.OnHidden();
        }
        else if (_focusRequested)
        {
            RequestMessageInputFocus();
        }
    }

    private void OnMessageInputLoaded(object sender, RoutedEventArgs args)
    {
        if (_focusRequested)
            RequestMessageInputFocus();
    }

    private void RequestMessageInputFocus()
    {
        _focusRequested = true;
        int generation = ++_focusGeneration;
        QueueInputFocus(generation, 3);
    }

    private void QueueInputFocus(int generation, int remaining)
    {
        DispatcherQueue.TryEnqueue(Microsoft.UI.Dispatching.DispatcherQueuePriority.Low, () =>
        {
            if (_isClosed || !_focusRequested || generation != _focusGeneration)
                return;
            if (HistoryInput.Focus(FocusState.Programmatic))
            {
                _focusRequested = false;
                HistoryInput.SelectionStart = HistoryInput.Text.Length;
            }
            else if (remaining > 0)
                QueueInputFocus(generation, remaining - 1);
        });
    }

    private void OnMessageInputLostFocus(object sender, RoutedEventArgs args) => ViewModel.Composer.OnHidden();

    private void OnMessageInputPreviewKeyDown(object sender, KeyRoutedEventArgs args)
    {
        if (_isComposing || args.Key != VirtualKey.Enter)
            return;
        if ((InputKeyboardSource.GetKeyStateForCurrentThread(VirtualKey.Shift)
            & Windows.UI.Core.CoreVirtualKeyStates.Down) != 0)
        {
            args.Handled = !ViewModel.Composer.CanAddLine;
            return;
        }
        args.Handled = true;
        if (ViewModel.Composer.SendCommand.CanExecute(null))
            ViewModel.Composer.SendCommand.Execute(null);
    }

    private void ApplyBackdrop()
    {
        SideyWindowTheme.ApplyBackdrop(this, HistoryFallbackBackground);
    }

    private void ApplyResponsiveSize()
    {
        WindowsMonitorInfo monitor = WindowsMonitorService.Select(
            _initialState.Preferences.OverlayRegion.MonitorIdentifier);
        ResponsiveWindowSize size = ResponsiveWindowSizePolicy.Calculate(
            monitor,
            SideyWindowKind.History);
        AppWindow.Resize(new Windows.Graphics.SizeInt32(size.Width, size.Height));
        AppWindow.Move(new Windows.Graphics.PointInt32(
            monitor.WorkAreaPixels.X + ((monitor.WorkAreaPixels.Width - size.Width) / 2),
            monitor.WorkAreaPixels.Y + ((monitor.WorkAreaPixels.Height - size.Height) / 2)));
    }

    private void OnHistoryContainerContentChanging(
        ListViewBase sender,
        ContainerContentChangingEventArgs args)
    {
        _ = sender;
        if (args.ItemIndex >= ViewModel.Items.Count - 5
            && ViewModel.LoadMoreCommand.CanExecute(null))
        {
            ViewModel.LoadMoreCommand.Execute(null);
        }
    }

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
        _focusRequested = false;
        _focusGeneration++;
        HistoryInput.Loaded -= OnMessageInputLoaded;
        Activated -= OnWindowActivated;
        HistoryRoot.DataContext = null;
        ViewModel.Dispose();
    }

    private void OnWindowClosed(object sender, WindowEventArgs args)
    {
        _ = sender;
        _ = args;
        PrepareForClose();
        AppWindow.Closing -= OnAppWindowClosing;
    }
}
