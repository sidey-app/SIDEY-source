using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Sidey.Core.Domain;
using Sidey.Platform.Windows;
using Windows.UI;

namespace Sidey.App.Controls;

public sealed partial class StoreProductArtwork : UserControl
{
    public static readonly DependencyProperty ProductKindProperty = DependencyProperty.Register(
        nameof(ProductKind), typeof(CommerceProductKind), typeof(StoreProductArtwork),
        new PropertyMetadata(CommerceProductKind.Character, OnProductChanged));
    public static readonly DependencyProperty CatalogItemIdProperty = DependencyProperty.Register(
        nameof(CatalogItemId), typeof(string), typeof(StoreProductArtwork),
        new PropertyMetadata(string.Empty, OnProductChanged));
    public static readonly DependencyProperty CharacterIdProperty = DependencyProperty.Register(
        nameof(CharacterId), typeof(string), typeof(StoreProductArtwork),
        new PropertyMetadata(PixelCharacterCatalog.FallbackId, OnProductChanged));

    private int _generation;
    private CancellationTokenSource? _loadCancellation;

    public StoreProductArtwork()
    {
        InitializeComponent();
        Loaded += OnLoaded;
        Unloaded += OnUnloaded;
    }

    public CommerceProductKind ProductKind
    {
        get => (CommerceProductKind)GetValue(ProductKindProperty);
        set => SetValue(ProductKindProperty, value);
    }

    public string CatalogItemId
    {
        get => (string)GetValue(CatalogItemIdProperty);
        set => SetValue(CatalogItemIdProperty, value);
    }

    public string CharacterId
    {
        get => (string)GetValue(CharacterIdProperty);
        set => SetValue(CharacterIdProperty, value);
    }

    private static void OnProductChanged(
        DependencyObject sender,
        DependencyPropertyChangedEventArgs args)
    {
        _ = args;
        var artwork = (StoreProductArtwork)sender;
        if (artwork.IsLoaded)
        {
            artwork.BeginReload();
        }
    }

    private void OnLoaded(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        SizeChanged -= OnArtworkSizeChanged;
        SizeChanged += OnArtworkSizeChanged;
        UpdateBubblePreviewSize();
        BeginReload();
    }

    private void OnArtworkSizeChanged(object sender, SizeChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        UpdateBubblePreviewSize();
    }

    private void UpdateBubblePreviewSize()
    {
        double pointSize = ActualHeight > 64 ? 82 : 56;
        BubblePreview.Width = pointSize;
        BubblePreview.Height = Math.Round(pointSize * 0.44);
    }

    private void BeginReload() => _ = ReloadAsync();

    private async Task ReloadAsync()
    {
        CancelPendingLoad();
        var cancellation = new CancellationTokenSource();
        _loadCancellation = cancellation;
        int generation = Interlocked.Increment(ref _generation);
        PreviewImage.Source = null;
        CannonEmitterImage.Source = null;
        CannonballImage.Source = null;
        CannonPreview.Visibility = Visibility.Collapsed;
        BubbleDecoration.Source = null;
        BubblePreview.Visibility = Visibility.Collapsed;
        try
        {
            (ImageSource? primary, ImageSource? secondary) = await LoadPreviewAsync(
                cancellation.Token);
            if (generation != Volatile.Read(ref _generation) || !IsLoaded)
            {
                return;
            }

            if (ProductKind == CommerceProductKind.Bubble)
            {
                ConfigureBubblePreview(primary);
            }
            else if (IsCannon())
            {
                CannonEmitterImage.Source = primary;
                CannonballImage.Source = secondary;
                CannonPreview.Visibility = Visibility.Visible;
            }
            else
            {
                PreviewImage.Width = ProductKind == CommerceProductKind.Character ? 72 : 48;
                PreviewImage.Height = PreviewImage.Width;
                PreviewImage.Source = primary;
            }
        }
        catch (OperationCanceledException) when (cancellation.IsCancellationRequested)
        {
        }
        catch (Exception exception)
        {
            StartupDiagnostics.NonFatal("store-artwork-load", exception);
            if (generation == Volatile.Read(ref _generation) && IsLoaded)
            {
                PreviewImage.Source = null;
            }
        }
        finally
        {
            if (ReferenceEquals(_loadCancellation, cancellation))
            {
                _loadCancellation = null;
                cancellation.Dispose();
            }
        }
    }

    private async Task<(ImageSource? Primary, ImageSource? Secondary)> LoadPreviewAsync(
        CancellationToken cancellationToken)
    {
        string root = Path.Combine(SideyDeploymentPaths.DeploymentRoot(), "Assets");
        if (ProductKind == CommerceProductKind.Character)
        {
            PixelCharacterDefinition definition = PixelCharacterCatalog.Get(CharacterId);
            string path = Path.Combine(
                root,
                definition.SpriteSheetResource.Replace('/', Path.DirectorySeparatorChar));
            return (await StorePreviewImageLoader.LoadFrameAsync(
                path,
                checked((uint)definition.FrameWidth),
                checked((uint)definition.FrameHeight),
                frame: 0,
                renderedWidth: 72,
                renderedHeight: 72,
                cancellationToken), null);
        }

        if (ProductKind == CommerceProductKind.Bubble)
        {
            if (string.IsNullOrEmpty(CatalogItemId))
            {
                return (null, null);
            }

            return (await StorePreviewImageLoader.LoadFrameAsync(
                Path.Combine(root, "Bubbles", CatalogItemId, "decoration.png"),
                frameWidth: 16,
                frameHeight: 16,
                frame: 0,
                renderedWidth: 16,
                renderedHeight: 16,
                cancellationToken), null);
        }

        string throwableId = CosmeticCatalog.ResolveThrowableAssetId(CatalogItemId);
        if (IsCannon())
        {
            ImageSource emitter = await StorePreviewImageLoader.LoadFrameAsync(
                Path.Combine(root, "Throwables", throwableId, "emitter.png"),
                frameWidth: 24,
                frameHeight: 24,
                frame: 2,
                renderedWidth: 48,
                renderedHeight: 48,
                cancellationToken);
            ImageSource cannonball = await StorePreviewImageLoader.LoadFrameAsync(
                Path.Combine(root, "Throwables", throwableId, "sprite.png"),
                frameWidth: 16,
                frameHeight: 16,
                frame: 1,
                renderedWidth: 24,
                renderedHeight: 24,
                cancellationToken);
            return (emitter, cannonball);
        }

        return (await StorePreviewImageLoader.LoadFrameAsync(
            Path.Combine(root, "Throwables", throwableId, "sprite.png"),
            frameWidth: 16,
            frameHeight: 16,
            frame: 0,
            renderedWidth: 48,
            renderedHeight: 48,
            cancellationToken), null);
    }

    private bool IsCannon() =>
        ProductKind == CommerceProductKind.Throwable
        && StringComparer.Ordinal.Equals(CatalogItemId, "throwable_toy_cannon");

    private void ConfigureBubblePreview(ImageSource? decoration)
    {
        (Color background, Color foreground) = CatalogItemId switch
        {
            "bubble_bunny_pink" =>
                (Color.FromArgb(255, 0xF7, 0xA9, 0xB8), Color.FromArgb(255, 0x1C, 0x1F, 0x29)),
            "bubble_butter_chick" =>
                (Color.FromArgb(255, 0xFF, 0xE3, 0x8A), Color.FromArgb(255, 0x1C, 0x1F, 0x29)),
            "bubble_starry_cat" =>
                (Color.FromArgb(255, 0x40, 0x3A, 0x78), Color.FromArgb(255, 0xFF, 0xF7, 0xE8)),
            _ =>
                (Color.FromArgb(242, 0xFF, 0xFF, 0xFF), Color.FromArgb(255, 0x1C, 0x1F, 0x29)),
        };
        BubblePreview.Background = new SolidColorBrush(background);
        BubblePreview.BorderBrush = new SolidColorBrush(Color.FromArgb(
            0x55,
            foreground.R,
            foreground.G,
            foreground.B));
        BubbleDecoration.Source = decoration;
        BubblePreview.Visibility = Visibility.Visible;
    }

    private void OnUnloaded(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        // A dialog can report Unloaded while the artwork remains in its live tree.
        // Wait for the tree to settle; a newer load invalidates this cleanup.
        int generation = Volatile.Read(ref _generation);
        if (!DispatcherQueue.TryEnqueue(() =>
        {
            if (!IsLoaded && generation == Volatile.Read(ref _generation))
            {
                ReleaseArtwork();
            }
        }))
        {
            ReleaseArtwork();
        }
    }

    private void ReleaseArtwork()
    {
        SizeChanged -= OnArtworkSizeChanged;
        CancelPendingLoad();
        Interlocked.Increment(ref _generation);
        PreviewImage.Source = null;
        CannonEmitterImage.Source = null;
        CannonballImage.Source = null;
        BubbleDecoration.Source = null;
    }

    private void CancelPendingLoad()
    {
        CancellationTokenSource? cancellation = _loadCancellation;
        _loadCancellation = null;
        if (cancellation is null)
        {
            return;
        }

        cancellation.Cancel();
        cancellation.Dispose();
    }

}
