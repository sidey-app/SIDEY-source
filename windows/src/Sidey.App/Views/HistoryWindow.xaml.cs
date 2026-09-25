using System.Collections.Specialized;
using Microsoft.UI.Input;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
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
    private bool _isVisible;
    private bool _isComposing;
    private bool _focusRequested;
    private int _focusGeneration;
    private ScrollViewer? _historyScroller;
    private long? _extentHeightCallbackToken;
    private long? _viewportHeightCallbackToken;
    private double _lastScrollableHeight;
    private bool _followLatest = true;
    private bool _historyPointerPressed;
    private double _historyPointerStartOffset;
    private bool _latestScrollQueued;
    private int _latestScrollGeneration;
    private readonly PointerEventHandler _historyWheelHandler;
    private readonly PointerEventHandler _historyPressHandler;
    private readonly PointerEventHandler _historyPointerEndedHandler;
    private readonly KeyEventHandler _historyKeyHandler;

    public HistoryWindow(HistoryWindowViewModel viewModel)
    {
        ViewModel = viewModel ?? throw new ArgumentNullException(nameof(viewModel));
        _initialState = viewModel.CurrentState;
        InitializeComponent();
        HistoryRoot.DataContext = ViewModel;
        HistoryInput.TextCompositionStarted += (_, _) => _isComposing = true;
        HistoryInput.TextCompositionEnded += (_, _) => _isComposing = false;
        HistoryInput.Loaded += OnMessageInputLoaded;
        _historyWheelHandler = OnHistoryWheel;
        _historyPressHandler = OnHistoryPress;
        _historyPointerEndedHandler = OnHistoryPointerEnded;
        _historyKeyHandler = OnHistoryKey;
        HistoryList.AddHandler(UIElement.PointerWheelChangedEvent, _historyWheelHandler, handledEventsToo: true);
        HistoryList.AddHandler(UIElement.PointerPressedEvent, _historyPressHandler, handledEventsToo: true);
        HistoryList.AddHandler(UIElement.PointerReleasedEvent, _historyPointerEndedHandler, handledEventsToo: true);
        HistoryList.AddHandler(UIElement.PointerCanceledEvent, _historyPointerEndedHandler, handledEventsToo: true);
        HistoryList.AddHandler(UIElement.PointerCaptureLostEvent, _historyPointerEndedHandler, handledEventsToo: true);
        HistoryList.AddHandler(UIElement.KeyDownEvent, _historyKeyHandler, handledEventsToo: true);
        ViewModel.Items.CollectionChanged += OnHistoryItemsChanged;
        Activated += OnWindowActivated;
        ApplyTheme(_initialState.Preferences.Theme);
        SideyWindowTheme.FollowTitleBarTheme(this, HistoryRoot);
        Title = I18n.Get("window.historyTitle");
        SideyWindowIcon.Apply(AppWindow);
        if (AppWindow.Presenter is OverlappedPresenter presenter)
        {
            KeepOnTopButton.IsChecked = presenter.IsAlwaysOnTop;
        }
        else
        {
            KeepOnTopButton.IsEnabled = false;
        }
        UpdateKeepOnTopLabel();
        ApplyResponsiveSize();
        ApplyBackdrop();
        AppWindow.Closing += OnAppWindowClosing;
        Closed += OnWindowClosed;
    }

    public HistoryWindowViewModel ViewModel { get; }

    public bool IsVisible => _isVisible && !_isClosed
        && (AppWindow.Presenter is not OverlappedPresenter presenter
            || presenter.State != OverlappedPresenterState.Minimized);

    public void RefreshLocalizedText()
    {
        ViewModel.RefreshLocalizedText();
        UpdateKeepOnTopLabel();
    }

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

        if (AppWindow.Presenter is OverlappedPresenter
            { State: OverlappedPresenterState.Minimized } presenter)
        {
            presenter.Restore();
        }

        _focusRequested = true;
        _isVisible = true;
        AppWindow.Show();
        Activate();
        SideyWindowActivation.BringToForeground(this);
        _ = ViewModel.ActivateAsync();
        ViewModel.Composer.OnShown();
        RequestMessageInputFocus();
    }

    public void HideHistory()
    {
        if (!IsVisible)
        {
            return;
        }

        _isVisible = false;
        _focusRequested = false;
        _focusGeneration++;
        _latestScrollGeneration++;
        _latestScrollQueued = false;
        ViewModel.Deactivate();
        AppWindow.Hide();
    }

    private void OnKeepOnTopClick(object sender, RoutedEventArgs args)
    {
        if (AppWindow.Presenter is OverlappedPresenter presenter)
        {
            presenter.IsAlwaysOnTop = KeepOnTopButton.IsChecked == true;
            UpdateKeepOnTopLabel();
        }
    }

    private void UpdateKeepOnTopLabel()
    {
        string label = I18n.Get(KeepOnTopButton.IsChecked == true
            ? "history.stopKeepingOnTop"
            : "history.keepOnTop");
        ToolTipService.SetToolTip(KeepOnTopButton, label);
        AutomationProperties.SetName(KeepOnTopButton, label);
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
        if (!_latestScrollQueued
            && _historyScroller is { VerticalOffset: <= 40 }
            && args.ItemIndex <= 4
            && ViewModel.LoadMoreCommand.CanExecute(null))
        {
            ViewModel.LoadMoreCommand.Execute(null);
        }
    }

    private void OnHistoryListLoaded(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        DetachHistoryScroller();
        _historyScroller = FindScrollViewer(HistoryList);
        if (_historyScroller is not null)
        {
            _lastScrollableHeight = _historyScroller.ScrollableHeight;
            _historyScroller.ViewChanged += OnHistoryScrollChanged;
            _extentHeightCallbackToken = _historyScroller.RegisterPropertyChangedCallback(
                ScrollViewer.ExtentHeightProperty, OnHistoryScrollGeometryChanged);
            _viewportHeightCallbackToken = _historyScroller.RegisterPropertyChangedCallback(
                ScrollViewer.ViewportHeightProperty, OnHistoryScrollGeometryChanged);
        }

        if (ViewModel.Items.Count > 0)
        {
            RequestScrollToLatest();
        }
    }

    private void OnHistoryItemsChanged(object? sender, NotifyCollectionChangedEventArgs args)
    {
        _ = sender;
        if (ViewModel.Items.Count == 0)
        {
            _followLatest = true;
            return;
        }

        bool newOwnMessage = args.Action == NotifyCollectionChangedAction.Add
            && args.NewItems is { Count: > 0 } newItems
            && args.NewStartingIndex == ViewModel.Items.Count - newItems.Count
            && newItems.OfType<HistoryEntryViewModel>().Any(item => item.IsCurrentUser);
        if (_followLatest || newOwnMessage)
        {
            RequestScrollToLatest();
        }
    }

    private void OnHistoryScrollChanged(object? sender, ScrollViewerViewChangedEventArgs args)
    {
        _ = args;
        if (!_latestScrollQueued && sender is ScrollViewer scroller)
        {
            // Late ListView measurement can move the bottom without user input.
            if (scroller.ScrollableHeight - scroller.VerticalOffset <= 4)
            {
                _followLatest = true;
            }
            else if (_historyPointerPressed
                && scroller.VerticalOffset < _historyPointerStartOffset - 1)
            {
                StopFollowingLatest();
            }
            if (scroller.VerticalOffset <= 40 && ViewModel.LoadMoreCommand.CanExecute(null))
            {
                ViewModel.LoadMoreCommand.Execute(null);
            }
        }
    }

    private void OnHistoryScrollGeometryChanged(DependencyObject sender, DependencyProperty property)
    {
        _ = property;
        if (_isClosed || !ReferenceEquals(sender, _historyScroller))
        {
            return;
        }

        double scrollableHeight = _historyScroller.ScrollableHeight;
        bool grew = scrollableHeight > _lastScrollableHeight + 1;
        if (grew || scrollableHeight < _lastScrollableHeight)
        {
            _lastScrollableHeight = scrollableHeight;
        }
        if (grew && _followLatest)
        {
            RequestScrollToLatest();
        }
    }

    private void OnHistoryWheel(object sender, PointerRoutedEventArgs args)
    {
        _ = sender;
        if (args.GetCurrentPoint(HistoryList).Properties.MouseWheelDelta > 0)
        {
            StopFollowingLatest();
        }
    }

    private void OnHistoryPress(object sender, PointerRoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        _historyPointerPressed = true;
        _historyPointerStartOffset = _historyScroller?.VerticalOffset ?? 0;
        if (_latestScrollQueued)
        {
            StopFollowingLatest();
        }
    }

    private void OnHistoryPointerEnded(object sender, PointerRoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (_historyPointerPressed && _historyScroller is { } scroller
            && scroller.VerticalOffset < _historyPointerStartOffset - 1)
        {
            StopFollowingLatest();
        }
        _historyPointerPressed = false;
    }

    private void DetachHistoryScroller()
    {
        if (_historyScroller is not { } scroller)
        {
            return;
        }

        scroller.ViewChanged -= OnHistoryScrollChanged;
        if (_extentHeightCallbackToken is { } extentToken)
        {
            scroller.UnregisterPropertyChangedCallback(ScrollViewer.ExtentHeightProperty, extentToken);
            _extentHeightCallbackToken = null;
        }
        if (_viewportHeightCallbackToken is { } viewportToken)
        {
            scroller.UnregisterPropertyChangedCallback(ScrollViewer.ViewportHeightProperty, viewportToken);
            _viewportHeightCallbackToken = null;
        }
        _historyScroller = null;
        _historyPointerPressed = false;
    }

    private void OnHistoryKey(object sender, KeyRoutedEventArgs args)
    {
        _ = sender;
        if (args.Key is VirtualKey.Up or VirtualKey.PageUp or VirtualKey.Home)
        {
            StopFollowingLatest();
        }
    }

    private void StopFollowingLatest()
    {
        _followLatest = false;
        _latestScrollGeneration++;
        _latestScrollQueued = false;
    }

    private void RequestScrollToLatest()
    {
        if (_isClosed || _latestScrollQueued || ViewModel.Items.Count == 0)
        {
            return;
        }

        _followLatest = true;
        _latestScrollQueued = true;
        int generation = ++_latestScrollGeneration;
        QueueLatestScroll(generation, remainingPasses: 2);
    }

    private void QueueLatestScroll(int generation, int remainingPasses)
    {
        if (!DispatcherQueue.TryEnqueue(Microsoft.UI.Dispatching.DispatcherQueuePriority.Low, () =>
            ScrollToLatest(generation, remainingPasses)))
        {
            _latestScrollQueued = false;
        }
    }

    private void ScrollToLatest(int generation, int remainingPasses)
    {
        if (_isClosed || generation != _latestScrollGeneration)
        {
            return;
        }

        if (ViewModel.Items.LastOrDefault() is { } latest)
        {
            HistoryList.ScrollIntoView(latest);
            HistoryList.UpdateLayout();
            _historyScroller ??= FindScrollViewer(HistoryList);
            _historyScroller?.ChangeView(null, _historyScroller.ScrollableHeight, null, disableAnimation: true);
        }

        if (remainingPasses > 0)
        {
            QueueLatestScroll(generation, remainingPasses - 1);
        }
        else
        {
            _latestScrollQueued = false;
            if (_historyScroller is { VerticalOffset: <= 40 }
                && ViewModel.LoadMoreCommand.CanExecute(null))
            {
                ViewModel.LoadMoreCommand.Execute(null);
            }
        }
    }

    private static ScrollViewer? FindScrollViewer(DependencyObject root)
    {
        if (root is ScrollViewer scroller)
        {
            return scroller;
        }

        for (int index = 0; index < VisualTreeHelper.GetChildrenCount(root); index++)
        {
            if (FindScrollViewer(VisualTreeHelper.GetChild(root, index)) is { } child)
            {
                return child;
            }
        }

        return null;
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
        _isVisible = false;
        _latestScrollGeneration++;
        ViewModel.Items.CollectionChanged -= OnHistoryItemsChanged;
        HistoryList.Loaded -= OnHistoryListLoaded;
        HistoryList.RemoveHandler(UIElement.PointerWheelChangedEvent, _historyWheelHandler);
        HistoryList.RemoveHandler(UIElement.PointerPressedEvent, _historyPressHandler);
        HistoryList.RemoveHandler(UIElement.PointerReleasedEvent, _historyPointerEndedHandler);
        HistoryList.RemoveHandler(UIElement.PointerCanceledEvent, _historyPointerEndedHandler);
        HistoryList.RemoveHandler(UIElement.PointerCaptureLostEvent, _historyPointerEndedHandler);
        HistoryList.RemoveHandler(UIElement.KeyDownEvent, _historyKeyHandler);
        DetachHistoryScroller();
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
