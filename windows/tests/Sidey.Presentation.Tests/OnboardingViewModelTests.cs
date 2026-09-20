using Sidey.Core.Abstractions;
using Sidey.Core.Domain;
using Sidey.Presentation.Services;
using Sidey.Presentation.ViewModels;

namespace Sidey.Presentation.Tests;

public sealed class OnboardingViewModelTests
{
    [Fact]
    public async Task GoogleButtonStaysDisabledWhileTheStoredSessionIsBeingChecked()
    {
        var coordinator = new FakeSideyCoordinator { State = CoordinatorState.Initial };
        using var viewModel = new OnboardingViewModel(coordinator);

        Assert.True(viewModel.IsGoogleChecking);
        Assert.False(viewModel.CanBegin);
        Assert.False(viewModel.BeginCommand.CanExecute(null));

        await viewModel.BeginCommand.ExecuteAsync(null);

        Assert.Equal(0, coordinator.GoogleStartCount);
        coordinator.State = coordinator.State with
        {
            GoogleAuthentication = GoogleAuthenticationState.Required,
        };
        viewModel.ApplyState(coordinator.State);
        Assert.False(viewModel.IsGoogleChecking);
        Assert.True(viewModel.BeginCommand.CanExecute(null));
    }

    [Fact]
    public async Task UnverifiedCompletedInstallationMustConnectBeforeSetupOrFinish()
    {
        var coordinator = new FakeSideyCoordinator
        {
            State = CoordinatorState.Initial with
            {
                GoogleAuthentication = GoogleAuthenticationState.Required,
                Preferences = AppPreferences.Default with { OnboardingCompleted = true },
                RealtimeConnection = ConnectedStatus(),
            },
        };
        using var viewModel = new OnboardingViewModel(coordinator);
        Assert.True(coordinator.State.NeedsOnboarding);
        await viewModel.BeginCommand.ExecuteAsync(null);
        Assert.Equal(1, coordinator.GoogleStartCount);
        Assert.True(viewModel.IsLanding);
        Assert.True(viewModel.IsGooglePending);
        Assert.False(viewModel.CanBegin);
        viewModel.Nickname = "친구";
        Assert.False(viewModel.CanSaveProfile);
        viewModel.Step = 3;
        await viewModel.FinishCommand.ExecuteAsync(null);
        Assert.Equal(0, coordinator.CompleteOnboardingCallCount);
        viewModel.ApplyState(coordinator.State);
        await viewModel.CancelGoogleCommand.ExecuteAsync(null);
        Assert.True(viewModel.IsLanding);
        Assert.True(viewModel.CanBegin);
        Assert.True(coordinator.State.Preferences.OnboardingCompleted);
    }

    [Fact]
    public void VerifiedNewInstallationAdvancesWhileExistingCompletedInstallationKeepsItsCompletion()
    {
        var coordinator = new FakeSideyCoordinator { State = CoordinatorState.Initial };
        using var viewModel = new OnboardingViewModel(coordinator);
        coordinator.State = coordinator.State with { GoogleAuthentication = GoogleAuthenticationState.Verified };
        viewModel.ApplyState(coordinator.State);
        Assert.True(viewModel.IsProfileStep);
        Assert.True(coordinator.State.NeedsOnboarding);
        Assert.False((coordinator.State with { Preferences = AppPreferences.Default with { OnboardingCompleted = true } }).NeedsOnboarding);
    }

    [Fact]
    public void CharacterPickerKeepsTheFiveFreeWindowsSelections()
    {
        var viewModel = new OnboardingViewModel(new FakeSideyCoordinator());

        Assert.Equal(
            ["pixel_hamster", "pixel_cat", "pixel_puppy", "pixel_rabbit", "pixel_penguin"],
            viewModel.CharacterSelections.Select(character => character.Id));
    }

    [Fact]
    public void IssuedCharactersAppearInTheOnboardingProfilePicker()
    {
        var coordinator = new FakeSideyCoordinator
        {
            State = CoordinatorState.Initial with
            {
                GoogleAuthentication = GoogleAuthenticationState.Verified,
                ActiveEntitlementKeys = new HashSet<string>(StringComparer.Ordinal)
                {
                    "character:pixel_starlight_upalupa",
                },
            },
        };

        var viewModel = new OnboardingViewModel(coordinator);

        Assert.Contains(
            viewModel.CharacterSelections,
            character => character.Id == "pixel_starlight_upalupa");
    }

    [Fact]
    public void NewInstallationStartsWithLandingThenMovesToProfile()
    {
        var viewModel = new OnboardingViewModel(new FakeSideyCoordinator());

        Assert.True(viewModel.IsLanding);

        viewModel.BeginCommand.Execute(null);

        Assert.True(viewModel.IsProfileStep);
        Assert.True(viewModel.IsSetupVisible);
    }

    [Fact]
    public async Task RestoredProfileAndGroupArePrefilledButRequireExplicitProgress()
    {
        var userId = Guid.NewGuid();
        var profile = new Profile(userId, "사이드", "pixel_cat");
        var room = new Room(
            Guid.NewGuid(),
            "친구들",
            userId,
            [new RoomMember(userId, profile.Nickname, profile.CharacterId, PresenceState.Online)],
            "ABCD",
            true,
            1);
        var coordinator = new FakeSideyCoordinator
        {
            State = CoordinatorState.Initial with
            {
                GoogleAuthentication = GoogleAuthenticationState.Verified,
                Profile = profile,
                Rooms = [room],
                ActiveRoomId = room.Id,
                RealtimeConnection = ConnectedStatus(),
            },
        };
        var viewModel = new OnboardingViewModel(coordinator);

        Assert.True(viewModel.IsLanding);
        Assert.Equal("사이드", viewModel.Nickname);
        Assert.Equal("pixel_cat", viewModel.SelectedCharacterId);
        Assert.Equal("친구들", viewModel.RoomName);

        viewModel.BeginCommand.Execute(null);

        Assert.True(viewModel.IsProfileStep);
        viewModel.ApplyState(coordinator.State with
        {
            Preferences = coordinator.State.Preferences with { OnboardingCompleted = true },
        });
        Assert.True(viewModel.IsProfileStep);

        await viewModel.SaveProfileCommand.ExecuteAsync(null);

        Assert.True(viewModel.IsGroupStep);
        viewModel.ApplyState(coordinator.State);
        Assert.True(viewModel.IsGroupStep);

        viewModel.SkipGroupCommand.Execute(null);

        Assert.True(viewModel.IsReadyStep);
        Assert.Equal(0, coordinator.CreateRoomCallCount);
        Assert.Equal(0, coordinator.JoinRoomCallCount);
    }

    [Fact]
    public async Task FinishingPersistsExplicitCompletionBeforeClosingOnboarding()
    {
        var coordinator = new FakeSideyCoordinator();
        var viewModel = new OnboardingViewModel(coordinator) { Step = 2 };
        bool completed = false;
        viewModel.Completed += () => completed = true;

        viewModel.SkipGroupCommand.Execute(null);
        await viewModel.FinishCommand.ExecuteAsync(null);

        Assert.True(viewModel.IsReadyStep);
        Assert.True(completed);
        Assert.Equal(1, coordinator.CompleteOnboardingCallCount);
    }

    [Fact]
    public async Task CompletionFailureKeepsTheReadyStepOpen()
    {
        var coordinator = new FakeSideyCoordinator
        {
            CompleteOnboardingHandler = _ => throw new IOException("설정을 저장하지 못했습니다."),
        };
        var viewModel = new OnboardingViewModel(coordinator) { Step = 3 };
        bool completed = false;
        viewModel.Completed += () => completed = true;

        await viewModel.FinishCommand.ExecuteAsync(null);

        Assert.False(completed);
        Assert.True(viewModel.IsReadyStep);
        Assert.Equal("설정을 저장하지 못했습니다.", viewModel.ErrorMessage);
    }

    [Fact]
    public async Task SuccessfulRoomCreationMovesToReadyStep()
    {
        var coordinator = new FakeSideyCoordinator
        {
            State = CoordinatorState.Initial with { GoogleAuthentication = GoogleAuthenticationState.Verified, RealtimeConnection = ConnectedStatus() },
        };
        var viewModel = new OnboardingViewModel(coordinator)
        {
            Step = 2,
            RoomName = "친구들",
        };

        await viewModel.CreateRoomCommand.ExecuteAsync(null);

        Assert.True(viewModel.IsReadyStep);
        Assert.Equal(1, coordinator.CreateRoomCallCount);
    }

    [Fact]
    public void ProfileActionRequiresConnectionAndValidNickname()
    {
        var coordinator = new FakeSideyCoordinator();
        var viewModel = new OnboardingViewModel(coordinator)
        {
            Nickname = "사이드",
        };

        Assert.False(viewModel.CanSaveProfile);

        viewModel.ApplyState(coordinator.State with { RealtimeConnection = ConnectedStatus() });

        Assert.True(viewModel.CanSaveProfile);
    }

    [Fact]
    public void StateUpdatePreservesUnsavedProfileDraft()
    {
        var profile = new Profile(Guid.NewGuid(), "saved-name", "pixel_hamster");
        var coordinator = new FakeSideyCoordinator
        {
            State = CoordinatorState.Initial with
            {
                GoogleAuthentication = GoogleAuthenticationState.Verified,
                Profile = profile,
                RealtimeConnection = ConnectedStatus(),
            },
        };
        var viewModel = new OnboardingViewModel(coordinator)
        {
            Nickname = "draft-name",
            SelectedCharacterId = "pixel_cat",
        };

        viewModel.ApplyState(coordinator.State with
        {
            RealtimeConnection = RealtimeConnectionStatus.Disconnected,
        });

        Assert.Equal("draft-name", viewModel.Nickname);
        Assert.Equal("pixel_cat", viewModel.SelectedCharacterId);
    }

    [Fact]
    public async Task DisposedViewModelIgnoresAnInFlightProfileCompletion()
    {
        var completion = new TaskCompletionSource(
            TaskCreationOptions.RunContinuationsAsynchronously);
        var coordinator = new FakeSideyCoordinator
        {
            State = CoordinatorState.Initial with { GoogleAuthentication = GoogleAuthenticationState.Verified, RealtimeConnection = ConnectedStatus() },
            SaveProfileHandler = (_, _, _) => completion.Task,
        };
        var viewModel = new OnboardingViewModel(coordinator)
        {
            Step = 1,
            Nickname = "sidey",
        };
        int propertyChanges = 0;
        viewModel.PropertyChanged += (_, _) => propertyChanges++;

        Task operation = viewModel.SaveProfileCommand.ExecuteAsync(null);
        Assert.Equal(1, coordinator.SaveProfileCallCount);
        viewModel.Dispose();
        int changesAtDispose = propertyChanges;

        completion.SetResult();
        await operation;

        Assert.Equal(1, viewModel.Step);
        Assert.Equal(changesAtDispose, propertyChanges);
    }

    private static RealtimeConnectionStatus ConnectedStatus() => new(true, true, true);
}
