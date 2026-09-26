using CommunityToolkit.Mvvm.ComponentModel;

namespace Sidey.Presentation.ViewModels;

public sealed partial class CharacterSelectionItemViewModel : ObservableObject
{
    public CharacterSelectionItemViewModel(string id, string displayName, string characterId)
    {
        Id = id;
        DisplayName = displayName;
        CharacterId = characterId;
    }

    public string Id { get; }

    [ObservableProperty]
    public partial string DisplayName { get; set; }

    public string CharacterId { get; }

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(SelectionStatus))]
    public partial bool IsSelected { get; set; }

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(SelectionStatus))]
    public partial bool IsPending { get; set; }

    public string SelectionStatus => IsPending ? Sidey.Core.Localization.I18n.Get("profile.applying")
        : IsSelected ? Sidey.Core.Localization.I18n.Get("profile.cosmetics.equipped") : string.Empty;
    public void RefreshSelectionStatus() => OnPropertyChanged(nameof(SelectionStatus));
    [ObservableProperty]
    public partial bool AnimationsEnabled { get; set; } = true;
    [ObservableProperty]
    public partial bool IsEnabled { get; set; } = true;
}
