using System.Diagnostics;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Sidey.Core.Domain;
using Sidey.Core.Localization;
using Sidey.Core.Overlay;
using Sidey.Platform.Windows;
using Windows.Foundation;
using Windows.UI;

namespace Sidey.App.Controls;

public sealed partial class StorePreviewStage : UserControl
{
    private const double StageWidth = 540;
    private const double PlatformTop = 256;
    private const double RenderedCharacterSize = 72;
    private const double PreviewScale = RenderedCharacterSize / 48d;
    private const double RenderedFootBaseline = 9;
    private const double ProjectileSize = 48;
    private const double ImpactSize = 72;
    private const double EmitterSize = 72;
    private const double ProjectilePathY = CharacterTop + (RenderedCharacterSize / 2d);
    private const double CharacterTop = PlatformTop - RenderedCharacterSize + RenderedFootBaseline;
    private const double WalkFrameSeconds = 0.16;
    private const double IdleFrameSeconds = 0.55;
    private const double TypingFrameSeconds = 0.35;
    private const double ThrowActionSeconds = 0.4;
    private const double ThrowReleaseSeconds = 0.2;
    private const double HitActionSeconds = 0.44;
    private string PreviewObjectId { get; }
    private double ImpactSeconds => CharacterImpactTiming.Duration(PreviewObjectId);
    private const double ProjectileRotationFrameSeconds = 0.083;
    private double ThrowCycleSeconds => Math.Max(1d,
        ThrowReleaseSeconds + ThrowFlightDuration(StageWidth * 0.22, StageWidth * 0.78) + ImpactSeconds);
    private const double FirstAutomaticThrowDelaySeconds = 0.35;
    private const double BubbleTangentMargin = 6;
    private const double BubbleMessageHeight = 42;
    private const double BubbleMessageFontSize = 16.5;
    private const double BubbleTypingWidth = 63;
    private const double BubbleTypingHeight = 45;
    private const double BubbleTypingFontSize = 24;
    private const double BubbleTailHeight = 12;
    private const double BubbleTailHalfBase = 9;
    private const double BubbleTailBaseInset = 15;
    private const double BubbleTailBodyOverlap = 3;
    private const double BubbleCharacterGap = 6;
    private const double BubbleDecorationLeadingOverflow = 12;
    private const double BubbleDecorationTopOverflow = 16;
    private const double NameplateHeight = 20;
    private const double NameplateTop = PlatformTop - CharacterNameplateLayout.DistanceFromFoot * 3 - NameplateHeight;
    private const double AmbientSparkleCycleSeconds = 1.2;
    private const double AmbientSparkleDurationSeconds = 1.05;
    private static readonly IReadOnlyList<RectD> s_noAvoidanceRects = [];
    private readonly HashSet<Guid> _stoppedIds = [];
    private bool _treeMovementPaused;
    private bool _previewSoundEnabled = true;

    private readonly DispatcherTimer _timer = new() { Interval = TimeSpan.FromMilliseconds(1000d / 30d) };
    private readonly Stopwatch _clock = new();
    private readonly Dictionary<string, IReadOnlyList<PixelFrameSurface>> _characters = new(StringComparer.Ordinal);
    private readonly Dictionary<string, IReadOnlyList<PixelFrameSurface>> _actions = new(StringComparer.Ordinal);
    private readonly List<NearestPixelImage> _leftCharacterLayers = [];
    private readonly List<NearestPixelImage> _rightCharacterLayers = [];
    private readonly List<PixelFrameSurface> _ownedFrames = [];
    private readonly List<ImageSource> _ownedImageFrames = [];
    private readonly EdgeTrackGeometry _movementGeometry = new(
        new RectD(0, 0, StageWidth, 280),
        OverlayEdge.Bottom,
        tangentExtent: RenderedCharacterSize * 3);
    private readonly List<PixelMovementAgent> _movementAgents = [];
    private readonly PixelMovementScratch _movementScratch = new();
    private readonly Random _random = new(0x51DE59);
    private readonly List<Microsoft.UI.Xaml.Shapes.Polygon> _sparkles = [];
    private readonly List<Microsoft.UI.Xaml.Shapes.Polygon> _pulseSparkles = [];
    private double _pulseStarted = double.NegativeInfinity;
    private double _manualThrowStartX;
    private CharacterThrowTrajectory _manualThrowTrajectory;
    private readonly CancellationToken _lifetimeToken;
    private IReadOnlyList<ImageSource> _projectileFrames = [];
    private IReadOnlyList<ImageSource> _emitterFrames = [];
    private double _manualThrowStarted = -10;
    private double _manualThrowFlightDuration = 0.55;
    private bool _manualThrowPending;
    private double ManualThrowSequenceSeconds => ThrowReleaseSeconds + _manualThrowFlightDuration
        + Math.Max(HitActionSeconds, ImpactSeconds);
    private double _lastSceneElapsed;
    private bool _resourcesLoaded;
    private bool _loadFailed;
    private bool _isPresented;
    private int _loadGeneration;
    private int _presentationGeneration;
    private CancellationTokenSource? _loadCancellation;
    private Task? _loadTask;
    private bool _leftFacingLeft;
    private bool _rightFacingLeft;
    private int _leftVisibleCharacterLayer = -1;
    private int _rightVisibleCharacterLayer = -1;
    private bool _animationsEnabled = true;
    private readonly CharacterStunState _stun;
    private readonly Guid _audioScope = Guid.NewGuid();
    private double _lastImpactStart = double.NegativeInfinity;
    private int _automaticSequence = -1;
    private bool _automaticSuppressed;
    private readonly Canvas _stunCanvas = new() { IsHitTestVisible = false };
    private readonly List<Microsoft.UI.Xaml.Shapes.Rectangle> _stunPixels = [];
    private readonly TextBlock _motionNotice = new() { FontSize = 11, TextWrapping = TextWrapping.Wrap, Width = 500, Visibility = Visibility.Collapsed };
    public event Action<string, Guid, long>? CharacterImpact;
    public event Action<Guid>? StopSounds;

    public StorePreviewStage(
        CommerceProductKind kind,
        string catalogItemId,
        string characterId,
        CancellationToken lifetimeToken = default)
    {
        InitializeComponent();
        _stun = new CharacterStunState(() => _clock.Elapsed.TotalSeconds);
        ProductKind = kind;
        CatalogItemId = catalogItemId;
        CharacterId = PixelCharacterCatalog.NormalizeId(characterId);
        PreviewObjectId = kind == CommerceProductKind.Throwable
            ? catalogItemId
            : WindowsCommerceCatalog.KeepsakeFor(CharacterId)?.EffectiveCatalogItemId ?? "patch_soft_ball";
        _lifetimeToken = lifetimeToken;
        TreeMovementHint.Visibility = ProductKind == CommerceProductKind.Character && CharacterId == "pixel_tree"
            ? Visibility.Visible : Visibility.Collapsed;
        PreviewSoundButton.Visibility = ProductKind == CommerceProductKind.Bubble ? Visibility.Collapsed : Visibility.Visible;
        RefreshSoundButton();
        _timer.Tick += OnTimerTick;
        BuildPlatform();
        BuildSparkles();
        BuildMovementAgents();
        SceneCanvas.Children.Add(_stunCanvas);
        Canvas.SetZIndex(_stunCanvas, 21);
        for (int i = 0; i < CharacterStunPixels.MaximumPixelCount * 2; i++)
        {
            var pixel = new Microsoft.UI.Xaml.Shapes.Rectangle { Width = 3, Height = 3, Visibility = Visibility.Collapsed };
            _stunPixels.Add(pixel);
            _stunCanvas.Children.Add(pixel);
        }
        Canvas.SetLeft(_motionNotice, 20);
        Canvas.SetTop(_motionNotice, CharacterId == "pixel_tree" ? 60 : 12);
        SceneCanvas.Children.Add(_motionNotice);
    }

    private void OnPreviewSoundClick(object sender, RoutedEventArgs args)
    {
        _previewSoundEnabled = !_previewSoundEnabled;
        if (!_previewSoundEnabled)
        {
            StopSounds?.Invoke(_audioScope);
        }
        RefreshSoundButton();
    }

    private void RefreshSoundButton()
    {
        string label = I18n.Get(_previewSoundEnabled ? "preview.muteSound" : "preview.enableSound");
        PreviewSoundIcon.Symbol = _previewSoundEnabled ? Symbol.Volume : Symbol.Mute;
        ToolTipService.SetToolTip(PreviewSoundButton, label);
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(PreviewSoundButton, label);
    }

    private void OnCharacterRightTapped(object sender, RightTappedRoutedEventArgs args)
    {
        if (ProductKind == CommerceProductKind.Character && CharacterId == "pixel_tree" && _isPresented && _resourcesLoaded)
        {
            _treeMovementPaused = !_treeMovementPaused;
            args.Handled = true;
            UpdateScene();
        }
    }

    public void SetAnimationsEnabled(bool enabled)
    {
        if (_animationsEnabled == enabled)
            return;
        _animationsEnabled = enabled;
        StopAnimation();
        StopSounds?.Invoke(_audioScope);
        _clock.Reset();
        _stun.Reset();
        _pulseStarted = double.NegativeInfinity;
        _manualThrowStarted = -10;
        _manualThrowPending = false;
        _lastImpactStart = double.NegativeInfinity;
        _automaticSequence = -1;
        _lastSceneElapsed = 0;
        _movementAgents.Clear();
        BuildMovementAgents();
        _motionNotice.Text = I18n.Get("motion.disabled");
        _motionNotice.Visibility = enabled ? Visibility.Collapsed : Visibility.Visible;
        if (_isPresented && _resourcesLoaded)
            StartAnimation();
    }

    public CommerceProductKind ProductKind { get; }
    public string CatalogItemId { get; }
    public string CharacterId { get; }

    public void BeginPresentation()
    {
        if (_isPresented)
        {
            return;
        }

        _isPresented = true;
        int presentationGeneration = Interlocked.Increment(ref _presentationGeneration);
        StartupDiagnostics.Stage($"store-preview-presentation-started generation={presentationGeneration}");
        _ = RunPresentationAsync(presentationGeneration);
    }

    public void EndPresentation()
    {
        if (!_isPresented)
        {
            return;
        }

        _isPresented = false;
        _manualThrowPending = false;
        _manualThrowStarted = -10;
        _lastImpactStart = double.NegativeInfinity;
        StopSounds?.Invoke(_audioScope);
        _stun.Reset();
        Interlocked.Increment(ref _presentationGeneration);
        StopAnimation();
        CancelPendingLoad();
        Interlocked.Increment(ref _loadGeneration);
        ReleasePixelFrames();
        StartupDiagnostics.Stage("store-preview-presentation-ended");
    }

    private async Task RunPresentationAsync(int presentationGeneration)
    {
        try
        {
            await InitializeAsync(presentationGeneration, _lifetimeToken);
        }
        catch (OperationCanceledException) when (
            !_isPresented || _lifetimeToken.IsCancellationRequested)
        {
            return;
        }

        if (IsCurrentPresentation(presentationGeneration) && _resourcesLoaded)
        {
            StartAnimation();
        }
    }

    private async Task InitializeAsync(
        int presentationGeneration,
        CancellationToken cancellationToken)
    {
        while (IsCurrentPresentation(presentationGeneration)
            && !_resourcesLoaded
            && !_loadFailed)
        {
            cancellationToken.ThrowIfCancellationRequested();
            Task loadTask = _loadTask ?? StartResourceLoad(cancellationToken);
            await loadTask;
            if (ReferenceEquals(_loadTask, loadTask))
            {
                _loadTask = null;
            }
        }
    }

    private Task StartResourceLoad(CancellationToken cancellationToken)
    {
        CancelPendingLoad();
        _loadFailed = false;
        LoadingRing.IsActive = true;
        LoadingRing.Visibility = Visibility.Visible;
        ErrorText.Visibility = Visibility.Collapsed;
        var cancellation = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        _loadCancellation = cancellation;
        int generation = Interlocked.Increment(ref _loadGeneration);
        StartupDiagnostics.Stage($"store-preview-load-started generation={generation}");
        return LoadResourcesAsync(generation, cancellation);
    }

    public void StartAnimation()
    {
        if (!_isPresented || !_resourcesLoaded)
        {
            return;
        }

        if (_animationsEnabled)
        {
            _clock.Start();
            _timer.Start();
        }
        UpdateScene();
    }

    public void StopAnimation()
    {
        _timer.Stop();
        _clock.Stop();
    }

    private async Task LoadResourcesAsync(
        int generation,
        CancellationTokenSource cancellation)
    {
        CancellationToken cancellationToken = cancellation.Token;
        try
        {
            string root = Path.Combine(SideyDeploymentPaths.DeploymentRoot(), "Assets");
            string leftId = ProductKind == CommerceProductKind.Character
                ? CharacterId
                : PixelCharacterCatalog.FallbackId;
            foreach (string id in new[] { leftId, "pixel_cat" }.Distinct(StringComparer.Ordinal))
            {
                PixelCharacterDefinition definition = PixelCharacterCatalog.Get(id);
                string path = Path.Combine(
                    root,
                    definition.SpriteSheetResource.Replace('/', Path.DirectorySeparatorChar));
                var frames = new PixelFrameSurface[10];
                for (int frame = 0; frame < frames.Length; frame++)
                {
                    frames[frame] = await LoadPixelFrameAsync(
                        path,
                        checked((uint)definition.FrameWidth),
                        checked((uint)definition.FrameHeight),
                        frame,
                        renderedWidth: checked((uint)RenderedCharacterSize),
                        renderedHeight: checked((uint)RenderedCharacterSize),
                        cancellationToken);
                }
                _characters[id] = frames;

                string actionPath = Path.Combine(root, "Characters", id, "throw_hit.png");
                var actionFrames = new PixelFrameSurface[8];
                for (int frame = 0; frame < actionFrames.Length; frame++)
                {
                    actionFrames[frame] = await LoadPixelFrameAsync(
                        actionPath,
                        frameWidth: 24,
                        frameHeight: 24,
                        frame,
                        renderedWidth: checked((uint)RenderedCharacterSize),
                        renderedHeight: checked((uint)RenderedCharacterSize),
                        cancellationToken);
                }
                _actions[id] = actionFrames;
            }

            if (ProductKind == CommerceProductKind.Bubble)
            {
                ImageSource bubbleDecoration = await StorePreviewImageLoader.LoadFrameAsync(
                    Path.Combine(root, "Bubbles", CatalogItemId, "decoration.png"),
                    frameWidth: 16,
                    frameHeight: 16,
                    frame: 0,
                    renderedWidth: 32,
                    renderedHeight: 32,
                    cancellationToken);
                ThrowIfLoadExpired(generation, cancellationToken);
                BubbleDecoration.Source = bubbleDecoration;
                ApplyBubbleColors();
            }
            else
            {
                string objectId = CosmeticCatalog.ResolveThrowableAssetId(PreviewObjectId);
                string objectPath = Path.Combine(root, "Throwables", objectId, "sprite.png");
                var projectileFrames = new ImageSource[12];
                for (int frame = 0; frame < projectileFrames.Length; frame++)
                {
                    projectileFrames[frame] = await LoadImageFrameAsync(
                        objectPath,
                        frameWidth: 16,
                        frameHeight: 16,
                        frame,
                        renderedWidth: frame < 8
                            ? checked((uint)ProjectileSize)
                            : checked((uint)ImpactSize),
                        renderedHeight: frame < 8
                            ? checked((uint)ProjectileSize)
                            : checked((uint)ImpactSize),
                        cancellationToken);
                }
                _projectileFrames = projectileFrames;
                ProjectileImage.SetFrames(projectileFrames.Take(8));
                ImpactImage.SetFrames(projectileFrames.Skip(8));

                if (objectId == "throwable_toy_cannon")
                {
                    string emitterPath = Path.Combine(root, "Throwables", objectId, "emitter.png");
                    var emitterFrames = new ImageSource[4];
                    for (int frame = 0; frame < emitterFrames.Length; frame++)
                    {
                        emitterFrames[frame] = await LoadImageFrameAsync(
                            emitterPath,
                            frameWidth: 24,
                            frameHeight: 24,
                            frame,
                            renderedWidth: checked((uint)EmitterSize),
                            renderedHeight: checked((uint)EmitterSize),
                            cancellationToken);
                    }
                    _emitterFrames = emitterFrames;
                    EmitterImage.SetFrames(emitterFrames);
                }
            }

            BuildCharacterLayers(
                LeftCharacterHost,
                _leftCharacterLayers,
                _characters[leftId],
                _actions[leftId]);
            BuildCharacterLayers(
                RightCharacterHost,
                _rightCharacterLayers,
                _characters["pixel_cat"],
                _actions["pixel_cat"]);
            _leftVisibleCharacterLayer = -1;
            _rightVisibleCharacterLayer = -1;

            ThrowIfLoadExpired(generation, cancellationToken);
            _resourcesLoaded = true;
            LoadingRing.IsActive = false;
            LoadingRing.Visibility = Visibility.Collapsed;
            SceneCanvas.Visibility = Visibility.Visible;
            UpdateScene();
            StartupDiagnostics.Stage($"store-preview-load-completed generation={generation}");
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            StartupDiagnostics.Stage($"store-preview-load-cancelled generation={generation}");
        }
        catch (Exception exception)
        {
            if (generation == Volatile.Read(ref _loadGeneration)
                && !cancellationToken.IsCancellationRequested)
            {
                _loadFailed = true;
                LoadingRing.IsActive = false;
                LoadingRing.Visibility = Visibility.Collapsed;
                ErrorText.Text = I18n.Get("store.previewUnavailable");
                ErrorText.Visibility = Visibility.Visible;
            }
            StartupDiagnostics.NonFatal("store-preview-load", exception);
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

    private bool IsCurrentPresentation(int generation) =>
        _isPresented && generation == Volatile.Read(ref _presentationGeneration);

    private async Task<PixelFrameSurface> LoadPixelFrameAsync(
        string path, uint frameWidth, uint frameHeight, int frame,
        uint renderedWidth, uint renderedHeight, CancellationToken cancellationToken)
    {
        PixelFrameSurface source = await StorePreviewImageLoader.LoadPixelFrameAsync(
            path, frameWidth, frameHeight, frame, renderedWidth, renderedHeight, cancellationToken);
        if (cancellationToken.IsCancellationRequested || !_isPresented)
        {
            source.Dispose();
            throw new OperationCanceledException(cancellationToken);
        }
        _ownedFrames.Add(source);
        return source;
    }

    private async Task<ImageSource> LoadImageFrameAsync(
        string path, uint frameWidth, uint frameHeight, int frame,
        uint renderedWidth, uint renderedHeight, CancellationToken cancellationToken)
    {
        ImageSource source = await StorePreviewImageLoader.LoadFrameAsync(
            path, frameWidth, frameHeight, frame, renderedWidth, renderedHeight, cancellationToken);
        if (cancellationToken.IsCancellationRequested || !_isPresented)
        {
            StorePreviewImageLoader.ReleaseFrame(source);
            throw new OperationCanceledException(cancellationToken);
        }
        _ownedImageFrames.Add(source);
        return source;
    }

    private void ReleasePixelFrames()
    {
        foreach (NearestPixelImage? layer in _leftCharacterLayers.Concat(_rightCharacterLayers))
            layer.Source = null;
        ProjectileImage.ClearFrames();
        ImpactImage.ClearFrames();
        EmitterImage.ClearFrames();
        foreach (ImageSource source in _ownedImageFrames)
            StorePreviewImageLoader.ReleaseFrame(source);
        _ownedImageFrames.Clear();
        LeftCharacterHost.Children.Clear();
        RightCharacterHost.Children.Clear();
        _leftCharacterLayers.Clear();
        _rightCharacterLayers.Clear();
        foreach (PixelFrameSurface source in _ownedFrames)
            source.Dispose();
        _ownedFrames.Clear();
        _characters.Clear();
        _actions.Clear();
        _projectileFrames = [];
        _emitterFrames = [];
        _resourcesLoaded = false;
    }

    private void ThrowIfLoadExpired(int generation, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        if (generation != Volatile.Read(ref _loadGeneration))
        {
            throw new OperationCanceledException(cancellationToken);
        }
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

    private void OnTimerTick(object? sender, object args)
    {
        _ = sender;
        _ = args;
        // A tick already queued on the dispatcher can arrive after StopAnimation.
        if (!_isPresented || !_timer.IsEnabled)
        {
            return;
        }
        UpdateScene();
    }

    private void UpdateScene()
    {
        if (!_resourcesLoaded)
        {
            return;
        }

        double elapsed = _clock.IsRunning ? _clock.Elapsed.TotalSeconds : 0;
        StartPendingPreviewThrow(elapsed);
        string leftId = ProductKind == CommerceProductKind.Character
            ? CharacterId
            : PixelCharacterCatalog.FallbackId;
        double leftX;
        double rightX;
        int leftFrame;
        int rightFrame;
        if (ProductKind == CommerceProductKind.Throwable)
        {
            leftX = (StageWidth * 0.22) - (RenderedCharacterSize / 2d);
            rightX = (StageWidth * 0.78) - (RenderedCharacterSize / 2d);
            leftFrame = CharacterFrame(elapsed, velocity: 0);
            rightFrame = CharacterFrame(elapsed + 0.08, velocity: 0);
        }
        else
        {
            if (_animationsEnabled)
                AdvanceMovement(elapsed);
            PixelMovementAgent leftAgent = _movementAgents[0];
            PixelMovementAgent rightAgent = _movementAgents[1];
            leftX = leftAgent.TrackPosition - (RenderedCharacterSize / 2d);
            rightX = rightAgent.TrackPosition - (RenderedCharacterSize / 2d);
            leftFrame = CharacterFrame(elapsed, PixelRoamingPolicy.IsWalking(leftAgent, _stoppedIds.Contains(leftAgent.Id), PreviewScale) ? leftAgent.Velocity : 0);
            rightFrame = CharacterFrame(elapsed + 0.08, PixelRoamingPolicy.IsWalking(rightAgent, _stoppedIds.Contains(rightAgent.Id), PreviewScale) ? rightAgent.Velocity : 0);
            if (elapsed - _manualThrowStarted >= ThrowActionSeconds)
            {
                UpdateFacing(leftAgent, leftId, ref _leftFacingLeft);
            }
            if (!_stoppedIds.Contains(rightAgent.Id))
            {
                UpdateFacing(rightAgent, "pixel_cat", ref _rightFacingLeft);
            }
        }

        double throwLocal = -1;
        bool leftToRight = true;
        if (ProductKind == CommerceProductKind.Throwable)
        {
            double sequenceTime = elapsed - FirstAutomaticThrowDelaySeconds;
            if (sequenceTime >= 0)
            {
                int sequenceIndex = (int)Math.Floor(sequenceTime / ThrowCycleSeconds);
                throwLocal = sequenceTime % ThrowCycleSeconds;
                leftToRight = sequenceIndex % 2 == 0;
                if (_automaticSequence != sequenceIndex)
                {
                    _automaticSequence = sequenceIndex;
                    _automaticSuppressed = _stun.IsStunned(_movementAgents[leftToRight ? 0 : 1].Id);
                }
                if (_automaticSuppressed)
                    throwLocal = -1;
            }
        }
        else if (ProductKind == CommerceProductKind.Character)
        {
            throwLocal = elapsed - _manualThrowStarted;
        }

        double flightDuration = ProductKind == CommerceProductKind.Character && throwLocal >= 0
            ? _manualThrowFlightDuration
            : ThrowFlightDuration(leftX, rightX);
        ApplyCharacterPose(
            _leftCharacterLayers,
            LeftCharacterScale,
            leftId,
            leftFrame,
            _leftFacingLeft,
            throwLocal,
            flightDuration,
            leftToRight,
            isLeftCharacter: true,
            ref _leftVisibleCharacterLayer);
        ApplyCharacterPose(
            _rightCharacterLayers,
            RightCharacterScale,
            "pixel_cat",
            rightFrame,
            _rightFacingLeft,
            throwLocal,
            flightDuration,
            leftToRight,
            isLeftCharacter: false,
            ref _rightVisibleCharacterLayer);

        PositionCharacters(leftX, rightX);
        double pulseScale = _animationsEnabled && !_stun.IsStunned(_movementAgents[0].Id) ? PreviewPulseScale(elapsed - _pulseStarted) : 1;
        LeftCharacterScale.ScaleX *= pulseScale;
        LeftCharacterScale.ScaleY = pulseScale;
        UpdateSparkles(elapsed, leftX, leftId);
        if (!_animationsEnabled || _stun.IsStunned(_movementAgents[0].Id))
            foreach (Microsoft.UI.Xaml.Shapes.Polygon? sparkle in _sparkles.Concat(_pulseSparkles))
                sparkle.Opacity = 0;
        UpdateStunPixels(leftX, rightX);

        if (ProductKind == CommerceProductKind.Bubble)
        {
            UpdateBubble(_animationsEnabled ? elapsed : 1.5, leftX, rightX);
            ProjectileImage.Opacity = 0;
            EmitterImage.Opacity = 0;
            ImpactImage.Opacity = 0;
            return;
        }

        BubblePreview.Visibility = Visibility.Collapsed;
        UpdateThrow(throwLocal, leftX, rightX, leftToRight, flightDuration);
    }

    private void UpdateStunPixels(double leftX, double rightX)
    {
        int index = 0;
        for (int side = 0; side < 2; side++)
        {
            if (_stun.Elapsed(_movementAgents[side].Id) is not { } elapsed)
                continue;
            foreach (StunPixel p in CharacterStunPixels.Create(elapsed, _animationsEnabled))
            {
                if (index >= _stunPixels.Count)
                    break;
                Microsoft.UI.Xaml.Shapes.Rectangle pixel = _stunPixels[index++];
                pixel.Fill = p.IsOutline ? s_stunOutlineBrush : p.IsStar ? s_stunStarBrush : s_stunRingBrush;
                Canvas.SetLeft(pixel, Math.Round(side == 0 ? leftX : rightX) + p.X * 3);
                Canvas.SetTop(pixel, CharacterTop + p.Y * 3);
                pixel.Visibility = Visibility.Visible;
            }
        }
        while (index < _stunPixels.Count)
            _stunPixels[index++].Visibility = Visibility.Collapsed;
    }
    private static readonly SolidColorBrush s_stunStarBrush = new(Color.FromArgb(255, 255, 224, 72));
    private static readonly SolidColorBrush s_stunOutlineBrush = new(Color.FromArgb(255, 130, 82, 12));
    private static readonly SolidColorBrush s_stunRingBrush = new(Color.FromArgb(255, 255, 175, 104));

    private void PositionCharacters(double leftX, double rightX)
    {
        Canvas.SetLeft(LeftCharacterHost, leftX);
        Canvas.SetTop(LeftCharacterHost, CharacterTop);
        Canvas.SetLeft(RightCharacterHost, rightX);
        Canvas.SetTop(RightCharacterHost, CharacterTop);
        PositionNameplate(LeftNameplate, leftX);
        PositionNameplate(RightNameplate, rightX);
    }

    private static void PositionNameplate(StackPanel nameplate, double characterLeft)
    {
        nameplate.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
        double width = nameplate.DesiredSize.Width;
        (double X, double Y) position = CharacterNameplateLayout.Position(
            (characterLeft + RenderedCharacterSize / 2, PlatformTop), width, NameplateHeight, 3, OverlayEdge.Bottom);
        Canvas.SetLeft(
            nameplate,
            Math.Clamp(
                position.X,
                BubbleTangentMargin,
                StageWidth - width - BubbleTangentMargin));
        Canvas.SetTop(nameplate, position.Y);
    }

    private void BuildMovementAgents()
    {
        double lower = _movementGeometry.TrackLowerBound;
        double leftFraction = ProductKind == CommerceProductKind.Bubble ? 0.28 : 0.22;
        double rightFraction = ProductKind == CommerceProductKind.Bubble ? 0.72 : 0.78;
        _movementAgents.Add(new PixelMovementAgent(
            new Guid("D5F0D9BB-FBDA-4B10-AEF9-A7E2A4CFBD25"),
            _movementGeometry.Clamp(StageWidth * leftFraction),
            RandomTarget(lower, _movementGeometry.TrackUpperBound),
            idleRemaining: _random.NextDouble() * 1.5d));
        _movementAgents.Add(new PixelMovementAgent(
            new Guid("26E5237A-69A1-4EA7-868E-822C831069B6"),
            _movementGeometry.Clamp(StageWidth * rightFraction),
            RandomTarget(lower, _movementGeometry.TrackUpperBound),
            idleRemaining: _random.NextDouble() * 1.5d));
    }

    private void AdvanceMovement(double elapsed)
    {
        double deltaTime = _lastSceneElapsed <= 0
            ? 1d / 30d
            : Math.Clamp(elapsed - _lastSceneElapsed, 0, 0.1);
        _lastSceneElapsed = elapsed;

        _stoppedIds.Clear();
        foreach (PixelMovementAgent agent in _movementAgents)
            if (_stun.IsStunned(agent.Id))
                _stoppedIds.Add(agent.Id);
        if (_treeMovementPaused && CharacterId == "pixel_tree")
        {
            _stoppedIds.Add(_movementAgents[0].Id);
        }
        double hitStarted = _manualThrowStarted + ThrowReleaseSeconds + _manualThrowFlightDuration;
        if (ProductKind == CommerceProductKind.Character
            && elapsed >= hitStarted && elapsed < hitStarted + HitActionSeconds)
        {
            _stoppedIds.Add(_movementAgents[1].Id);
        }

        PixelMovementSimulation.Step(
            _movementAgents,
            deltaTime,
            _movementGeometry,
            s_noAvoidanceRects,
            _stoppedIds,
            _movementScratch,
            PreviewScale);
        PixelRoamingPolicy.UpdateAfterMovement(
            _movementAgents, _stoppedIds, _movementGeometry, _random, PreviewScale);
    }

    private double RandomTarget(double lower, double upper) =>
        lower + (_random.NextDouble() * (upper - lower));

    private static int CharacterFrame(double elapsed, double velocity) =>
        Math.Abs(velocity) > 2
            ? 2 + ((int)(elapsed / WalkFrameSeconds) % 4)
            : (int)(elapsed / IdleFrameSeconds) % 2;

    private static void UpdateFacing(
        PixelMovementAgent agent,
        string characterId,
        ref bool facingLeft)
    {
        if (!PixelCharacterCatalog.Get(characterId).MirrorsToMovementDirection)
        {
            facingLeft = false;
            return;
        }

        if (Math.Abs(agent.Velocity) > 2d * PreviewScale)
        {
            facingLeft = agent.Velocity < 0d;
        }
    }

    private static void ApplyCharacterFrame(
        IReadOnlyList<NearestPixelImage> layers,
        ScaleTransform transform,
        string characterId,
        int frame,
        bool facingLeft,
        ref int visibleLayer)
    {
        ShowCharacterLayer(layers, Math.Clamp(frame, 0, 9), ref visibleLayer);
        transform.ScaleX = PixelCharacterCatalog.Get(characterId).MirrorsToMovementDirection
            && facingLeft
                ? -1
                : 1;
    }

    private static void ApplyActionFrame(
        IReadOnlyList<NearestPixelImage> layers,
        ScaleTransform transform,
        string characterId,
        int frame,
        bool facingLeft,
        ref int visibleLayer)
    {
        ShowCharacterLayer(layers, 10 + Math.Clamp(frame, 0, 7), ref visibleLayer);
        transform.ScaleX = PixelCharacterCatalog.Get(characterId).MirrorsToMovementDirection
            && facingLeft
                ? -1
                : 1;
    }

    private void ApplyCharacterPose(
        IReadOnlyList<NearestPixelImage> layers,
        ScaleTransform transform,
        string characterId,
        int baseFrame,
        bool facingLeft,
        double throwLocal,
        double flightDuration,
        bool leftToRight,
        bool isLeftCharacter,
        ref int visibleLayer)
    {
        if (_stun.Elapsed(_movementAgents[isLeftCharacter ? 0 : 1].Id) is { } stunElapsed)
        {
            Range range = PixelCharacterCatalog.Get(characterId).Frames.Offline;
            int frame = range.Start.Value + (_animationsEnabled ? (int)(stunElapsed / 1.2) % (range.End.Value - range.Start.Value) : 0);
            ApplyCharacterFrame(layers, transform, characterId, frame, facingLeft, ref visibleLayer);
            return;
        }
        bool isActor = leftToRight == isLeftCharacter;
        if (isActor && throwLocal is >= 0 and < ThrowActionSeconds)
        {
            int actionFrame = Math.Min(
                3,
                (int)(throwLocal / (ThrowActionSeconds / 4d)));
            ApplyActionFrame(
                layers,
                transform,
                characterId,
                actionFrame,
                facingLeft,
                ref visibleLayer);
            return;
        }

        double impactStarted = ThrowReleaseSeconds + flightDuration;
        if (!isActor
            && throwLocal >= impactStarted
            && throwLocal < impactStarted + HitActionSeconds)
        {
            int hitFrame = 4 + Math.Min(
                3,
                (int)((throwLocal - impactStarted) / (HitActionSeconds / 4d)));
            ApplyActionFrame(
                layers,
                transform,
                characterId,
                hitFrame,
                facingLeft,
                ref visibleLayer);
            return;
        }

        ApplyCharacterFrame(
            layers,
            transform,
            characterId,
            baseFrame,
            facingLeft,
            ref visibleLayer);
    }

    private static void BuildCharacterLayers(
        Grid host,
        List<NearestPixelImage> layers,
        IReadOnlyList<PixelFrameSurface> movementFrames,
        IReadOnlyList<PixelFrameSurface> actionFrames)
    {
        host.Children.Clear();
        layers.Clear();
        foreach (PixelFrameSurface source in movementFrames.Concat(actionFrames))
        {
            var layer = new NearestPixelImage
            {
                Width = RenderedCharacterSize,
                Height = RenderedCharacterSize,
                Source = source,
                Opacity = 0,
                IsHitTestVisible = false,
            };
            layers.Add(layer);
            host.Children.Add(layer);
        }
    }

    private static void ShowCharacterLayer(
        IReadOnlyList<NearestPixelImage> layers,
        int requestedLayer,
        ref int visibleLayer)
    {
        if (requestedLayer == visibleLayer || layers.Count == 0)
        {
            return;
        }

        if (visibleLayer >= 0 && visibleLayer < layers.Count)
        {
            layers[visibleLayer].Opacity = 0;
        }
        int nextLayer = Math.Clamp(requestedLayer, 0, layers.Count - 1);
        layers[nextLayer].Opacity = 1;
        visibleLayer = nextLayer;
    }

    private static void SetImageSource(NearestPixelImage image, PixelFrameSurface source)
    {
        if (!ReferenceEquals(image.Source, source))
        {
            image.Source = source;
        }
    }

    private void UpdateBubble(double elapsed, double leftX, double rightX)
    {
        double phase = elapsed % 6;
        bool fromLeft = phase < 3;
        double local = phase % 3;
        bool typing = local < 1;
        BubbleText.Text = typing
            ? new string('.', 1 + ((int)(local / TypingFrameSeconds) % 3))
            : I18n.Get(fromLeft ? "preview.leftMessage" : "preview.rightMessage");
        BubbleText.FontSize = typing ? BubbleTypingFontSize : BubbleMessageFontSize;
        BubbleText.Margin = typing
            ? new Thickness(6, 1.5, 6, 1.5)
            : new Thickness(12, 10.5, 12, 10.5);
        BubbleText.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
        double bubbleWidth = typing
            ? BubbleTypingWidth
            : Math.Clamp(Math.Ceiling(BubbleText.DesiredSize.Width), 42, 330);
        double bubbleHeight = typing
            ? BubbleTypingHeight
            : Math.Max(BubbleMessageHeight, Math.Ceiling(BubbleText.DesiredSize.Height));
        double decorationLeadingOverflow = BubbleDecorationLeadingOverflow;
        double decorationTopOverflow = BubbleDecorationTopOverflow;
        BubblePreview.Width = bubbleWidth + decorationLeadingOverflow;
        BubblePreview.Height = decorationTopOverflow
            + bubbleHeight
            + BubbleTailHeight
            - BubbleTailBodyOverlap;
        BubbleBody.Width = bubbleWidth;
        BubbleBody.Height = bubbleHeight;
        BubbleBody.CornerRadius = new CornerRadius(13.5);
        Canvas.SetLeft(BubbleBody, decorationLeadingOverflow);
        Canvas.SetTop(BubbleBody, decorationTopOverflow);
        BubbleDecoration.Visibility = Visibility.Visible;
        Canvas.SetLeft(BubbleDecoration, 0);
        Canvas.SetTop(BubbleDecoration, 0);

        double senderCenter = (fromLeft ? leftX : rightX) + (RenderedCharacterSize / 2d);
        double halfWidth = bubbleWidth / 2d;
        double minimumCenter = halfWidth + BubbleTangentMargin + decorationLeadingOverflow;
        double maximumCenter = Math.Max(
            minimumCenter,
            StageWidth - halfWidth - BubbleTangentMargin);
        double bodyCenter = Math.Clamp(senderCenter, minimumCenter, maximumCenter);
        double bodyLeft = bodyCenter - halfWidth;
        double visualLeft = bodyLeft - decorationLeadingOverflow;
        double tailBaseCenter = Math.Clamp(
            senderCenter,
            bodyLeft + BubbleTailBaseInset,
            bodyLeft + bubbleWidth - BubbleTailBaseInset);
        double tailBaseY = decorationTopOverflow + bubbleHeight - BubbleTailBodyOverlap;
        BubbleTail.Points =
        [
            new Point(tailBaseCenter - BubbleTailHalfBase - visualLeft, tailBaseY),
            new Point(senderCenter - visualLeft, tailBaseY + BubbleTailHeight),
            new Point(tailBaseCenter + BubbleTailHalfBase - visualLeft, tailBaseY),
        ];
        Canvas.SetLeft(BubbleTail, 0);
        Canvas.SetTop(BubbleTail, 0);
        Canvas.SetLeft(BubblePreview, visualLeft);
        double bodyTop = NameplateTop
            - BubbleCharacterGap
            - BubbleTailHeight
            - bubbleHeight;
        Canvas.SetTop(BubblePreview, bodyTop - decorationTopOverflow);
        BubblePreview.Visibility = Visibility.Visible;
    }

    private void UpdateThrow(
        double local,
        double leftX,
        double rightX,
        bool leftToRight,
        double flightDuration)
    {
        ImpactImage.Opacity = 0;
        double sequenceEnd = ProductKind == CommerceProductKind.Throwable
            ? ThrowCycleSeconds
            : ThrowReleaseSeconds + flightDuration + Math.Max(HitActionSeconds, ImpactSeconds);
        if (!_animationsEnabled || local < 0 || local >= sequenceEnd || _projectileFrames.Count < 12)
        {
            ProjectileImage.Opacity = 0;
            EmitterImage.Opacity = 0;
            return;
        }

        double impactStarted = ThrowReleaseSeconds + flightDuration;

        if (local >= ThrowReleaseSeconds && local < impactStarted)
        {
            double startCenterX = leftToRight
                ? leftX + (RenderedCharacterSize / 2d)
                : rightX + (RenderedCharacterSize / 2d);
            double endCenterX = leftToRight
                ? rightX + (RenderedCharacterSize / 2d)
                : leftX + (RenderedCharacterSize / 2d);
            CharacterThrowTrajectory trajectory = ProductKind == CommerceProductKind.Character
                ? _manualThrowTrajectory
                : new CharacterThrowTrajectory((startCenterX, ProjectilePathY), (endCenterX, ProjectilePathY), PreviewScale);
            (double centerX, double centerY) = trajectory.PointAt(
                (endCenterX, ProjectilePathY), local - ThrowReleaseSeconds, OverlayEdge.Bottom);
            int projectileFrame = (int)((local - ThrowReleaseSeconds) / ProjectileRotationFrameSeconds) % 8;
            ProjectileImage.ShowFrame(projectileFrame);
            ProjectileScale.ScaleX = 1;
            Canvas.SetLeft(ProjectileImage, centerX - (ProjectileSize / 2d));
            Canvas.SetTop(ProjectileImage, centerY - (ProjectileSize / 2d));
            ProjectileImage.Opacity = 1;
        }
        else
        {
            ProjectileImage.Opacity = 0;
        }

        if (local >= impactStarted && local < impactStarted + ImpactSeconds)
        {
            double eventStart = ProductKind == CommerceProductKind.Throwable ? _automaticSequence : _manualThrowStarted;
            if (eventStart != _lastImpactStart)
            {
                _lastImpactStart = eventStart;
                Guid target = _movementAgents[leftToRight ? 1 : 0].Id;
                _stun.RecordHit(target);
                string soundId = ImpactSoundCatalog.Resolve(CharacterId, PreviewObjectId);
                if (_previewSoundEnabled)
                {
                    CharacterImpact?.Invoke(soundId, _audioScope, Stopwatch.GetTimestamp());
                }
            }
            int impactFrame = 8 + CharacterImpactTiming.Frame(PreviewObjectId, local - impactStarted);
            ImpactImage.ShowFrame(impactFrame - 8);
            double targetCenterX = (leftToRight ? rightX : leftX)
                + (RenderedCharacterSize / 2d);
            Canvas.SetLeft(ImpactImage, targetCenterX - (ImpactSize / 2d));
            Canvas.SetTop(ImpactImage, ProjectilePathY - (10 * PreviewScale) - (ImpactSize / 2d));
            ImpactImage.Opacity = 1;
        }

        if (_emitterFrames.Count == 4 && local < ThrowActionSeconds)
        {
            int emitterFrame = Math.Min(3, (int)(local / (ThrowActionSeconds / 4d)));
            EmitterImage.ShowFrame(emitterFrame);
            EmitterScale.ScaleX = leftToRight ? 1 : -1;
            double actorCenterX = (leftToRight ? leftX : rightX)
                + (RenderedCharacterSize / 2d);
            (double X, double Y) emitterCenter = CannonEmitterLayout.Center(
                (actorCenterX, ProjectilePathY), !leftToRight, OverlayEdge.Bottom, PreviewScale);
            Canvas.SetLeft(EmitterImage, emitterCenter.X - (EmitterSize / 2d));
            Canvas.SetTop(EmitterImage, emitterCenter.Y - (EmitterSize / 2d));
            EmitterImage.Opacity = 1;
        }
        else
        {
            EmitterImage.Opacity = 0;
        }
    }

    private static double ThrowFlightDuration(double leftX, double rightX)
    {
        return new CharacterThrowTrajectory((leftX, 0d), (rightX, 0d), PreviewScale).DurationSeconds;
    }

    private void ApplyBubbleColors()
    {
        (Color background, Color foreground) = CatalogItemId switch
        {
            "bubble_bunny_pink" =>
                (Color.FromArgb(255, 0xF7, 0xA9, 0xB8), Color.FromArgb(255, 0x1C, 0x1F, 0x29)),
            "bubble_butter_chick" =>
                (Color.FromArgb(255, 0xFF, 0xE3, 0x8A), Color.FromArgb(255, 0x1C, 0x1F, 0x29)),
            _ =>
                (Color.FromArgb(255, 0x40, 0x3A, 0x78), Color.FromArgb(255, 0xFF, 0xF7, 0xE8)),
        };
        background = Color.FromArgb(245, background.R, background.G, background.B);
        var backgroundBrush = new SolidColorBrush(background);
        BubbleBody.Background = backgroundBrush;
        BubbleTail.Fill = backgroundBrush;
        BubbleText.Foreground = new SolidColorBrush(foreground);
    }

    private void BuildPlatform()
    {
        var baseBrush = new SolidColorBrush(Color.FromArgb(255, 0xB8, 0xBA, 0xBF));
        var alternateBrush = new SolidColorBrush(Color.FromArgb(255, 0xCD, 0xD0, 0xD3));
        PlatformCanvas.Background = baseBrush;
        const int Pixel = 4;
        for (int row = 0; row < 6; row += 2)
        {
            for (int column = 0; column < StageWidth / Pixel; column++)
            {
                if ((column % 2 == 0) == (row % 4 == 0))
                {
                    var tile = new Microsoft.UI.Xaml.Shapes.Rectangle
                    {
                        Width = Pixel,
                        Height = Pixel,
                        Fill = alternateBrush,
                    };
                    Canvas.SetLeft(tile, column * Pixel);
                    Canvas.SetTop(tile, row * Pixel);
                    PlatformCanvas.Children.Add(tile);
                }
            }
        }
    }

    private void BuildSparkles()
    {
        Color[] colors =
        [
            Color.FromArgb(255, 120, 194, 173),
            Color.FromArgb(255, 168, 135, 214),
            Color.FromArgb(255, 245, 186, 56),
        ];
        bool hasPulseEffect = ProductKind == CommerceProductKind.Character
            && PixelCharacterCatalog.Get(CharacterId).VisualEffect == PixelCharacterVisualEffect.StarlightSparkles;
        for (int index = 0; index < (hasPulseEffect ? 49 : 6); index++)
        {
            double radius = 3 + ((index % 3) * 0.5);
            var star = new Microsoft.UI.Xaml.Shapes.Polygon
            {
                Fill = new SolidColorBrush(colors[index % colors.Length]),
                Points =
                [
                    new Point(radius, 0),
                    new Point(radius + 1, radius - 1),
                    new Point(radius * 2, radius),
                    new Point(radius + 1, radius + 1),
                    new Point(radius, radius * 2),
                    new Point(radius - 1, radius + 1),
                    new Point(0, radius),
                    new Point(radius - 1, radius - 1),
                ],
                Opacity = 0,
                RenderTransform = new ScaleTransform { CenterX = radius, CenterY = radius },
            };
            if (index < 6)
                _sparkles.Add(star);
            else
                _pulseSparkles.Add(star);
            SparkleCanvas.Children.Add(star);
        }
    }

    private void UpdateSparkles(double elapsed, double leftX, string leftId)
    {
        bool active = PixelCharacterCatalog.Get(leftId).VisualEffect
            == PixelCharacterVisualEffect.StarlightSparkles;
        SparkleCanvas.Visibility = active ? Visibility.Visible : Visibility.Collapsed;
        if (!active)
        {
            return;
        }

        for (int index = 0; index < _sparkles.Count; index++)
        {
            Microsoft.UI.Xaml.Shapes.Polygon star = _sparkles[index];
            (double Tangent, double Normal, double Radius, double Opacity) particle = StarlightSparkleLayout.Ambient(elapsed, index, 0x51DE59);
            double radius = 3 + ((index % 3) * 0.5);
            (double X, double Y) point = StarlightSparkleLayout.Point(
                (leftX + (RenderedCharacterSize / 2d), ProjectilePathY),
                particle.Tangent * PreviewScale, particle.Normal * PreviewScale, OverlayEdge.Bottom);
            Canvas.SetLeft(star, point.X - radius);
            Canvas.SetTop(star, point.Y - radius);
            var scale = (ScaleTransform)star.RenderTransform;
            scale.ScaleX = scale.ScaleY = particle.Radius * PreviewScale / radius;
            star.Opacity = particle.Opacity;
        }
        UpdatePulseSparkles(elapsed - _pulseStarted, leftX);
    }

    private void UpdatePulseSparkles(double elapsed, double leftX)
    {
        for (int index = 0; index < _pulseSparkles.Count; index++)
        {
            Microsoft.UI.Xaml.Shapes.Polygon star = _pulseSparkles[index];
            if (elapsed < 0 || elapsed >= 0.78)
            {
                star.Opacity = 0;
                continue;
            }
            double progress = elapsed / 0.78;
            double centerX = leftX + (RenderedCharacterSize / 2d);
            double centerY = ProjectilePathY;
            double radius;
            if (index == 0)
            {
                double flash = Math.Clamp(elapsed / 0.32, 0, 1);
                radius = 34 * (0.25 + (0.75 * flash));
                star.Opacity = Math.Sin(Math.PI * flash) * 0.75;
            }
            else
            {
                bool outer = index <= 18;
                int waveIndex = outer ? index - 1 : index - 19;
                int count = outer ? 18 : 24;
                double waveProgress = outer ? progress : Math.Clamp((elapsed - 0.06) / 0.72, 0, 1);
                double angle = (waveIndex * Math.PI * 2 / count) + (outer ? 0 : Math.PI / count);
                double distance = (outer ? 126 + (42 * Unit(index * 3253)) : 82 + (50 * Unit(index * 3253)))
                    * Math.Sin(waveProgress * Math.PI / 2);
                centerX += Math.Cos(angle) * distance;
                centerY += Math.Sin(angle) * distance;
                radius = (outer ? 8 : 4.5) * (1 - (waveProgress * 0.7));
                star.Opacity = Math.Min(1, waveProgress / 0.12) * (1 - (waveProgress * waveProgress));
            }
            double originalRadius = 3 + (((index + 6) % 3) * 0.5);
            var scale = (ScaleTransform)star.RenderTransform;
            scale.ScaleX = scale.ScaleY = radius / originalRadius;
            Canvas.SetLeft(star, centerX - originalRadius);
            Canvas.SetTop(star, centerY - originalRadius);
        }
    }

    private static double Unit(int value)
    {
        uint mixed = (uint)value;
        mixed ^= mixed >> 16;
        mixed *= 0x7FEB352D;
        mixed ^= mixed >> 15;
        mixed *= 0x846CA68B;
        mixed ^= mixed >> 16;
        return mixed / (double)uint.MaxValue;
    }

    private void OnFriendTapped(object sender, TappedRoutedEventArgs args)
    {
        args.Handled = TriggerPreviewThrow();
    }

    private bool TriggerPreviewThrow()
    {
        if (!_animationsEnabled || _stun.IsStunned(_movementAgents[0].Id))
            return false;
        if (ProductKind == CommerceProductKind.Character && _resourcesLoaded && _isPresented)
        {
            // Coalesce rapid taps into one follow-up. Never replace a projectile or
            // truncate its hit/impact animation while the current throw is active.
            _manualThrowPending = true;
            UpdateScene();
            return true;
        }
        return false;
    }

    private void StartPendingPreviewThrow(double elapsed)
    {
        if (!_manualThrowPending || !_animationsEnabled || !_isPresented
            || ProductKind != CommerceProductKind.Character
            || elapsed - _manualThrowStarted < ManualThrowSequenceSeconds)
            return;

        _manualThrowPending = false;
        if (_stun.IsStunned(_movementAgents[0].Id))
            return;

        _manualThrowStartX = _movementAgents[0].TrackPosition;
        _manualThrowTrajectory = new CharacterThrowTrajectory(
            (_manualThrowStartX, ProjectilePathY),
            (_movementAgents[1].TrackPosition, ProjectilePathY), PreviewScale);
        _manualThrowFlightDuration = _manualThrowTrajectory.DurationSeconds;
        _manualThrowStarted = elapsed;
    }

    private void OnCharacterDoubleTapped(object sender, DoubleTappedRoutedEventArgs args)
    {
        args.Handled = TriggerPreviewPulse();
    }

    private bool TriggerPreviewPulse()
    {
        if (!_animationsEnabled || _stun.IsStunned(_movementAgents[0].Id))
            return false;
        if (ProductKind != CommerceProductKind.Character || !_resourcesLoaded || !_isPresented)
        {
            return false;
        }
        _pulseStarted = _clock.Elapsed.TotalSeconds;
        UpdateScene();
        return true;
    }

    private static double PreviewPulseScale(double elapsed)
    {
        if (elapsed < 0 || elapsed >= 0.8)
            return 1;
        if (elapsed <= 0.2)
        {
            double progress = elapsed / 0.2;
            return 1 + (2 * Math.Sin(progress * Math.PI / 2));
        }
        double settle = (elapsed - 0.2) / 0.6;
        return 2 + Math.Cos(settle * Math.PI);
    }

}
