using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Sidey.Core.Domain;
using Sidey.Core.Localization;

namespace Sidey.Presentation.ViewModels;

public sealed partial class StoreProductPreviewViewModel : ObservableObject
{
    private readonly AsyncRelayCommand _actionCommand;

    public StoreProductPreviewViewModel(
        CommerceProduct product,
        string displayName,
        string description,
        string formattedPrice,
        Func<Task> action,
        Action preview)
    {
        ProductId = product.Id;
        IsKeepsake = product.RelatedCharacterProductId is not null;
        CharacterId = product.CharacterId;
        Kind = product.Kind;
        CatalogItemId = product.EffectiveCatalogItemId;
        SortOrder = product.SortOrder;
        AmountKrw = product.AmountKrw;
        DisplayName = displayName;
        Description = description;
        FormattedPrice = formattedPrice;
        _actionCommand = new AsyncRelayCommand(action, () => IsActionEnabled);
        ActionCommand = _actionCommand;
        PreviewCommand = new RelayCommand(preview);
    }

    public StoreProductPreviewViewModel? RelatedKeepsake { get; internal set; }
    public string DetailStatusText => IsOwned ? I18n.Get("store.owned")
        : IsPreviewOnlyVisible ? I18n.Get("store.comingSoon") : ActionText;

    public bool IsKeepsake { get; }
    public string ProductId { get; }
    public string CharacterId { get; }
    public CommerceProductKind Kind { get; }
    public string CatalogItemId { get; }
    public int SortOrder { get; }
    public int AmountKrw { get; private set; }
    [ObservableProperty]
    public partial string DisplayName { get; set; }
    [ObservableProperty]
    public partial string Description { get; set; }
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(DetailStatusText))]
    public partial string FormattedPrice { get; set; }
    public IAsyncRelayCommand ActionCommand { get; }
    public IRelayCommand PreviewCommand { get; }

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(DetailStatusText))]
    public partial string ActionText { get; set; } = string.Empty;

    [ObservableProperty]
    public partial bool IsActionEnabled { get; set; }

    [ObservableProperty]
    public partial bool IsWorking { get; set; }

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(DetailStatusText))]
    public partial bool IsPreviewOnlyVisible { get; set; } = true;

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(DetailStatusText))]
    public partial bool IsOwned { get; set; }

    public void Apply(CommerceProductState state, bool commerceEnabled, bool isOwned)
    {
        AmountKrw = state.Product.AmountKrw;
        FormattedPrice = I18n.Format("store.priceKrw", AmountKrw);
        IsPreviewOnlyVisible = !commerceEnabled;
        IsOwned = isOwned;
        IsWorking = state.IsWorking;
        bool isActionEnabled = commerceEnabled
            && !isOwned
            && !state.IsWorking
            && state.PurchaseState is (
                CommercePurchaseState.Unavailable
                or CommercePurchaseState.GoogleConnectionRequired
                or CommercePurchaseState.Available
                or CommercePurchaseState.Refunded
                or CommercePurchaseState.Error);
        bool actionAvailabilityChanged = IsActionEnabled != isActionEnabled;
        IsActionEnabled = isActionEnabled;
        ActionText = isOwned ? I18n.Get("store.owned") : state.PurchaseState switch
        {
            CommercePurchaseState.Unavailable when commerceEnabled => I18n.Get("store.retry"),
            CommercePurchaseState.GoogleConnectionRequired => I18n.Get("store.retry"),
            CommercePurchaseState.Available or CommercePurchaseState.Refunded =>
                I18n.Format("store.purchase", FormattedPrice),
            CommercePurchaseState.OpeningCheckout => I18n.Get("store.openingCheckout"),
            CommercePurchaseState.Confirming => I18n.Get("store.confirming"),
            CommercePurchaseState.Owned => I18n.Get("store.owned"),
            CommercePurchaseState.Error => I18n.Get("store.retry"),
            _ => I18n.Get("store.comingSoon"),
        };
        if (actionAvailabilityChanged)
        {
            _actionCommand.NotifyCanExecuteChanged();
        }
    }
}
