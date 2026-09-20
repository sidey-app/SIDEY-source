using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Sidey.Core.Domain;
using Sidey.Core.Localization;
using Sidey.Presentation.Services;

namespace Sidey.Presentation.ViewModels;

public sealed partial class OnboardingViewModel : ObservableObject, IDisposable
{
    private readonly IOnboardingCoordinator _coordinator;
    private bool _disposed;
    private CoordinatorState _state;
    private string _syncedProfileNickname = string.Empty;
    private string _syncedProfileCharacterId = PixelCharacterCatalog.FallbackId;
    private string _syncedRoomName = string.Empty;

    public OnboardingViewModel(IOnboardingCoordinator coordinator)
    {
        _coordinator = coordinator ?? throw new ArgumentNullException(nameof(coordinator));
        _state = coordinator.State;
        ApplyState(coordinator.State);
    }

    public event Action? Completed;

    public ObservableCollection<CharacterSelectionItemViewModel> CharacterSelections { get; } = [];

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(IsLanding))]
    [NotifyPropertyChangedFor(nameof(IsSetupVisible))]
    [NotifyPropertyChangedFor(nameof(IsProfileStep))]
    [NotifyPropertyChangedFor(nameof(IsGroupStep))]
    [NotifyPropertyChangedFor(nameof(IsReadyStep))]
    [NotifyPropertyChangedFor(nameof(CanGoBack))]
    [NotifyCanExecuteChangedFor(nameof(SkipGroupCommand))]
    public partial int Step { get; set; }

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(CanSaveProfile))]
    public partial string Nickname { get; set; } = string.Empty;

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(CanSaveProfile))]
    public partial string SelectedCharacterId { get; set; } = PixelCharacterCatalog.FallbackId;

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(CanCreateRoom))]
    public partial string RoomName { get; set; } = string.Empty;

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(CanJoinRoom))]
    public partial string InviteCode { get; set; } = string.Empty;

    [ObservableProperty]
    public partial int GroupPathIndex { get; set; }

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(CanSaveProfile))]
    [NotifyPropertyChangedFor(nameof(CanCreateRoom))]
    [NotifyPropertyChangedFor(nameof(CanJoinRoom))]
    public partial bool IsConnected { get; set; }

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(CanSaveProfile))]
    [NotifyPropertyChangedFor(nameof(CanCreateRoom))]
    [NotifyPropertyChangedFor(nameof(CanJoinRoom))]
    [NotifyCanExecuteChangedFor(nameof(SkipGroupCommand))]
    public partial bool IsWorking { get; set; }

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(HasError))]
    public partial string? ErrorMessage { get; set; }

    public bool IsGooglePending => _state.GoogleAuthentication == GoogleAuthenticationState.SigningIn;
    public bool IsGoogleChecking => _state.GoogleAuthentication == GoogleAuthenticationState.Checking;
    public bool CanBegin => !IsWorking
        && _state.GoogleAuthentication is GoogleAuthenticationState.Required or GoogleAuthenticationState.Verified;
    public string BeginLabel => I18n.Get(_state.GoogleVerified ? "onboarding.getStarted" : "onboarding.googleContinue");

    public bool IsLanding => Step == 0;

    public bool IsSetupVisible => Step > 0;

    public bool IsProfileStep => Step == 1;

    public bool IsGroupStep => Step == 2;

    public bool IsReadyStep => Step == 3;

    public bool HasError => !string.IsNullOrWhiteSpace(ErrorMessage);

    public bool CanGoBack => Step is 1 or 2;

    public bool CanSaveProfile =>
        _state.GoogleVerified
        && IsConnected
        && !IsWorking
        && ProfileValidator.IsValidNickname(Nickname);

    public bool CanCreateRoom =>
        _state.GoogleVerified
        && IsConnected
        && !IsWorking
        && RoomNameValidator.IsValid(RoomName);

    public bool CanJoinRoom =>
        _state.GoogleVerified
        && IsConnected
        && !IsWorking
        && !string.IsNullOrWhiteSpace(InviteCode);

    public string ConnectionText => IsConnected
        ? I18n.Get("onboarding.serverConnected")
        : I18n.Get("onboarding.serverConnecting");

    public void ApplyState(CoordinatorState state)
    {
        if (_disposed)
        {
            return;
        }

        bool shouldApplyProfileDraft = ProfileDraftMatchesSyncedState();
        (string syncedNickname, string syncedCharacterId) = GetSyncedProfileDraft(state);
        bool shouldApplyRoomDraft = StringComparer.Ordinal.Equals(RoomName, _syncedRoomName);
        string syncedRoomName = GetSyncedRoomName(state);
        _syncedProfileNickname = syncedNickname;
        _syncedProfileCharacterId = syncedCharacterId;
        _syncedRoomName = syncedRoomName;

        bool becameVerified = !_state.GoogleVerified && state.GoogleVerified;
        _state = state;
        if (!state.GoogleVerified)
            Step = 0;
        else if (becameVerified && !state.Preferences.OnboardingCompleted)
            Step = 1;
        OnPropertyChanged(nameof(IsGooglePending));
        OnPropertyChanged(nameof(IsGoogleChecking));
        OnPropertyChanged(nameof(CanBegin));
        OnPropertyChanged(nameof(BeginLabel));
        BeginCommand.NotifyCanExecuteChanged();
        RefreshCharacterSelections(state.ActiveEntitlementKeys);
        IsConnected = state.Connected;
        OnPropertyChanged(nameof(ConnectionText));

        if (shouldApplyProfileDraft)
        {
            Nickname = syncedNickname;
            SelectedCharacterId = syncedCharacterId;
        }
        if (shouldApplyRoomDraft)
        {
            RoomName = syncedRoomName;
        }

        UpdateCharacterSelectionState();

        if (!string.IsNullOrWhiteSpace(state.ErrorMessage))
        {
            ErrorMessage = state.ErrorMessage;
        }

        RaiseActionAvailability();
    }

    public void ReportError(Exception exception)
    {
        if (!_disposed)
        {
            ErrorMessage = exception.Message;
        }
    }

    [RelayCommand(CanExecute = nameof(CanBegin))]
    private async Task BeginAsync()
    {
        if (_disposed || !CanBegin)
            return;
        if (_state.GoogleVerified)
        {
            ErrorMessage = null;
            Step = 1;
            return;
        }
        await RunAsync(async () =>
        {
            await _coordinator.BeginGoogleAuthenticationAsync();
            ApplyState(_coordinator.State);
        });
    }

    [RelayCommand]
    private async Task CancelGoogleAsync()
    {
        if (_disposed || !IsGooglePending)
            return;
        await RunAsync(async () =>
        {
            await _coordinator.CancelGoogleAuthenticationAsync();
            ApplyState(_coordinator.State);
        });
    }

    [RelayCommand]
    private void Back()
    {
        if (_disposed)
        {
            return;
        }

        ErrorMessage = null;
        if (Step == 2)
        {
            Step = 1;
        }
        else if (Step == 1)
        {
            Step = 0;
        }
    }

    [RelayCommand]
    private async Task SaveProfileAsync()
    {
        if (_disposed || !CanSaveProfile)
        {
            return;
        }

        await RunAsync(async () =>
        {
            await _coordinator.SaveProfileAsync(Nickname, SelectedCharacterId);
            if (_disposed)
            {
                return;
            }
            ApplyState(_coordinator.State);
            Step = 2;
        });
    }

    [RelayCommand]
    private async Task CreateRoomAsync()
    {
        if (_disposed || !CanCreateRoom)
        {
            return;
        }

        await RunAsync(async () =>
        {
            await _coordinator.CreateRoomAsync(RoomName);
            if (_disposed)
            {
                return;
            }
            ApplyState(_coordinator.State);
            Step = 3;
        });
    }

    [RelayCommand]
    private async Task JoinRoomAsync()
    {
        if (_disposed || !CanJoinRoom)
        {
            return;
        }

        await RunAsync(async () =>
        {
            await _coordinator.JoinRoomAsync(InviteCode.Trim().ToUpperInvariant());
            if (_disposed)
            {
                return;
            }
            ApplyState(_coordinator.State);
            Step = 3;
        });
    }

    [RelayCommand(CanExecute = nameof(CanSkipGroup))]
    private void SkipGroup()
    {
        if (_disposed)
        {
            return;
        }

        ErrorMessage = null;
        Step = 3;
    }

    private bool CanSkipGroup() => _state.GoogleVerified && Step == 2 && !IsWorking;

    [RelayCommand(AllowConcurrentExecutions = false)]
    private async Task FinishAsync()
    {
        if (_disposed || !_state.GoogleVerified || Step != 3)
        {
            return;
        }

        await RunAsync(async () =>
        {
            await _coordinator.CompleteOnboardingAsync();
            if (!_disposed)
            {
                Completed?.Invoke();
            }
        });
    }

    partial void OnIsWorkingChanged(bool value)
    {
        OnPropertyChanged(nameof(CanBegin));
        BeginCommand.NotifyCanExecuteChanged();
    }

    partial void OnSelectedCharacterIdChanged(string value) => UpdateCharacterSelectionState();

    partial void OnInviteCodeChanged(string value)
    {
        string normalized = value.ToUpperInvariant();
        if (!StringComparer.Ordinal.Equals(value, normalized))
        {
            InviteCode = normalized;
        }
    }

    private async Task RunAsync(Func<Task> action)
    {
        if (_disposed)
        {
            return;
        }

        IsWorking = true;
        ErrorMessage = null;
        try
        {
            await action();
        }
        catch (Exception exception)
        {
            if (!_disposed)
            {
                ErrorMessage = exception.Message;
            }
        }
        finally
        {
            if (!_disposed)
            {
                IsWorking = false;
            }
        }
    }

    public void Dispose()
    {
        _disposed = true;
        Completed = null;
    }

    private void UpdateCharacterSelectionState()
    {
        foreach (CharacterSelectionItemViewModel character in CharacterSelections)
        {
            character.IsSelected = StringComparer.Ordinal.Equals(
                character.Id,
                SelectedCharacterId);
        }
    }

    private void RefreshCharacterSelections(IReadOnlySet<string> activeEntitlementKeys)
    {
        IReadOnlyList<PixelCharacterDefinition> desired =
            PixelCharacterCatalog.SelectableFor(activeEntitlementKeys);
        if (CharacterSelections.Select(character => character.Id)
            .SequenceEqual(desired.Select(character => character.Id), StringComparer.Ordinal))
        {
            return;
        }

        CharacterSelections.Clear();
        foreach (PixelCharacterDefinition character in desired)
        {
            CharacterSelections.Add(new CharacterSelectionItemViewModel(
                character.Id,
                character.DisplayName,
                character.Id));
        }
    }

    private bool ProfileDraftMatchesSyncedState() =>
        StringComparer.Ordinal.Equals(Nickname, _syncedProfileNickname)
        && StringComparer.Ordinal.Equals(SelectedCharacterId, _syncedProfileCharacterId);

    private static (string Nickname, string CharacterId) GetSyncedProfileDraft(
        CoordinatorState state) =>
    (
        state.Profile?.Nickname ?? state.Preferences.CachedNickname ?? string.Empty,
        PixelCharacterCatalog.NormalizeId(
            state.Profile?.CharacterId ?? state.Preferences.CachedCharacterId)
    );

    private static string GetSyncedRoomName(CoordinatorState state) =>
        (state.ActiveRoomId is { } activeRoomId
            ? state.Rooms.FirstOrDefault(room => room.Id == activeRoomId)
            : null)?.Name
        ?? state.Rooms.FirstOrDefault()?.Name
        ?? string.Empty;

    private void RaiseActionAvailability()
    {
        OnPropertyChanged(nameof(CanSaveProfile));
        OnPropertyChanged(nameof(CanCreateRoom));
        OnPropertyChanged(nameof(CanJoinRoom));
    }
}
