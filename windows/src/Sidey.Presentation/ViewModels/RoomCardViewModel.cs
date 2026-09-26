using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Sidey.Core.Domain;
using Sidey.Core.Localization;
using Sidey.Presentation.Services;

namespace Sidey.Presentation.ViewModels;

public sealed class RoomCardViewModel : ObservableObject, IDisposable
{
    private Room _room;
    private string _name = string.Empty;
    private string _details = string.Empty;
    private bool _isActive;
    private bool _canJoin;
    private bool _isOwner;
    private bool _isExpanded;
    private string _expansionGlyph = string.Empty;
    private string _expansionActionText = string.Empty;
    private string _inviteActionText = string.Empty;
    private string _defaultInviteActionText = string.Empty;
    private bool _isInviteActionEnabled;
    private string _joinActionText = string.Empty;
    private bool _isJoinEnabled;
    private bool _isSwitching;
    private bool _areRoomActionsEnabled;
    private bool _areOwnerActionsEnabled;
    private bool _isInviteCopyConfirmed;
    private DelayedAction? _inviteCopyFeedback;

    public RoomCardViewModel(
        Room room,
        IAsyncRelayCommand joinCommand,
        IRelayCommand toggleCommand,
        IAsyncRelayCommand inviteCommand,
        IAsyncRelayCommand leaveCommand,
        IAsyncRelayCommand renameCommand,
        IAsyncRelayCommand deleteCommand)
    {
        _room = room;
        JoinCommand = joinCommand;
        ToggleCommand = toggleCommand;
        InviteCommand = inviteCommand;
        LeaveCommand = leaveCommand;
        RenameCommand = renameCommand;
        DeleteCommand = deleteCommand;
        foreach (IAsyncRelayCommand command in new[]
        {
            JoinCommand,
            InviteCommand,
            LeaveCommand,
            RenameCommand,
            DeleteCommand,
        })
        {
            command.PropertyChanged += (_, args) =>
            {
                if (args.PropertyName == nameof(IAsyncRelayCommand.IsRunning))
                {
                    OnPropertyChanged(nameof(IsJoinEnabled));
                    OnPropertyChanged(nameof(IsInviteActionEnabled));
                    OnPropertyChanged(nameof(AreRoomActionsEnabled));
                    OnPropertyChanged(nameof(AreOwnerActionsEnabled));
                }
            };
        }
    }

    public Room Room => _room;

    public string Name
    {
        get => _name;
        private set => SetProperty(ref _name, value);
    }

    public string Details
    {
        get => _details;
        private set => SetProperty(ref _details, value);
    }

    public bool IsActive
    {
        get => _isActive;
        private set => SetProperty(ref _isActive, value);
    }

    public bool CanJoin
    {
        get => _canJoin;
        private set => SetProperty(ref _canJoin, value);
    }

    public bool IsOwner
    {
        get => _isOwner;
        private set => SetProperty(ref _isOwner, value);
    }

    public bool IsExpanded
    {
        get => _isExpanded;
        private set => SetProperty(ref _isExpanded, value);
    }

    public string ExpansionGlyph
    {
        get => _expansionGlyph;
        private set => SetProperty(ref _expansionGlyph, value);
    }

    public string ExpansionActionText
    {
        get => _expansionActionText;
        private set => SetProperty(ref _expansionActionText, value);
    }

    public string InviteActionText
    {
        get => _inviteActionText;
        private set => SetProperty(ref _inviteActionText, value);
    }

    public bool IsInviteActionEnabled
    {
        get => _isInviteActionEnabled && !InviteCommand.IsRunning;
        private set => SetProperty(ref _isInviteActionEnabled, value);
    }

    public string JoinActionText
    {
        get => _joinActionText;
        private set => SetProperty(ref _joinActionText, value);
    }

    public bool IsJoinEnabled
    {
        get => _isJoinEnabled && !JoinCommand.IsRunning;
        private set => SetProperty(ref _isJoinEnabled, value);
    }

    public bool IsSwitching
    {
        get => _isSwitching;
        private set => SetProperty(ref _isSwitching, value);
    }

    public bool AreOwnerActionsEnabled
    {
        get => _areOwnerActionsEnabled
            && !RenameCommand.IsRunning
            && !DeleteCommand.IsRunning;
        private set => SetProperty(ref _areOwnerActionsEnabled, value);
    }

    public bool AreRoomActionsEnabled
    {
        get => _areRoomActionsEnabled && !LeaveCommand.IsRunning;
        private set => SetProperty(ref _areRoomActionsEnabled, value);
    }

    public bool IsInviteCopyConfirmed
    {
        get => _isInviteCopyConfirmed;
        private set => SetProperty(ref _isInviteCopyConfirmed, value);
    }

    public ObservableCollection<RoomMemberCardViewModel> Members { get; } = [];

    public IAsyncRelayCommand JoinCommand { get; }

    public IRelayCommand ToggleCommand { get; }

    public IAsyncRelayCommand InviteCommand { get; }

    public IAsyncRelayCommand LeaveCommand { get; }

    public IAsyncRelayCommand RenameCommand { get; }

    public IAsyncRelayCommand DeleteCommand { get; }

    internal void Update(
        Room room,
        string details,
        bool isActive,
        bool isOwner,
        bool isExpanded,
        string joinActionText,
        bool isJoinEnabled,
        bool isSwitching,
        string inviteActionText,
        bool isInviteActionEnabled,
        bool areRoomActionsEnabled,
        bool areOwnerActionsEnabled,
        IReadOnlyList<RoomMemberCardViewModel> members)
    {
        _room = room;
        Name = room.Name;
        Details = details;
        IsActive = isActive;
        CanJoin = !isActive;
        IsOwner = isOwner;
        IsExpanded = isExpanded;
        JoinActionText = joinActionText;
        IsJoinEnabled = isJoinEnabled;
        IsSwitching = isSwitching;
        ExpansionGlyph = isExpanded ? "\uE70E" : "\uE70D";
        ExpansionActionText = isExpanded
            ? I18n.Get("groups.collapse")
            : I18n.Get("groups.expand");
        _defaultInviteActionText = inviteActionText;
        if (!IsInviteCopyConfirmed)
        {
            InviteActionText = inviteActionText;
        }
        IsInviteActionEnabled = isInviteActionEnabled;
        AreRoomActionsEnabled = areRoomActionsEnabled;
        AreOwnerActionsEnabled = areOwnerActionsEnabled;
        UpdateMembers(members);
    }

    internal void ShowInviteCopyConfirmation()
    {
        _inviteCopyFeedback?.Cancel();
        InviteActionText = I18n.Get("groups.invite.copy.complete");
        IsInviteCopyConfirmed = true;
        DelayedAction? feedback = null;
        feedback = DelayedAction.Start(
            TimeSpan.FromSeconds(3),
            () =>
            {
                if (!ReferenceEquals(_inviteCopyFeedback, feedback))
                {
                    return;
                }

                IsInviteCopyConfirmed = false;
                InviteActionText = _defaultInviteActionText;
                _inviteCopyFeedback = null;
            });
        _inviteCopyFeedback = feedback;
    }

    public void Dispose()
    {
        _inviteCopyFeedback?.Cancel();
        _inviteCopyFeedback = null;
    }

    private void UpdateMembers(IReadOnlyList<RoomMemberCardViewModel> desiredMembers)
    {
        var desiredIds = desiredMembers.Select(member => member.UserId).ToHashSet();
        for (int index = Members.Count - 1; index >= 0; index--)
        {
            if (!desiredIds.Contains(Members[index].UserId))
            {
                Members.RemoveAt(index);
            }
        }

        for (int index = 0; index < desiredMembers.Count; index++)
        {
            RoomMemberCardViewModel desired = desiredMembers[index];
            int existingIndex = IndexOfMember(desired.UserId);
            if (existingIndex < 0)
            {
                Members.Insert(index, desired);
                continue;
            }

            if (existingIndex != index)
            {
                Members.Move(existingIndex, index);
            }

            if (!MemberPresentation(Members[index]).Equals(MemberPresentation(desired)))
            {
                Members[index] = desired;
            }
        }
    }

    private int IndexOfMember(Guid userId)
    {
        for (int index = 0; index < Members.Count; index++)
        {
            if (Members[index].UserId == userId)
            {
                return index;
            }
        }

        return -1;
    }

    private static (
        Guid RoomId,
        Guid UserId,
        string Nickname,
        string CharacterId,
        bool IsOwner,
        bool IsCurrentUser,
        bool CanRemove) MemberPresentation(RoomMemberCardViewModel member) =>
    (
        member.RoomId,
        member.UserId,
        member.Nickname,
        member.CharacterId,
        member.IsOwner,
        member.IsCurrentUser,
        member.CanRemove
    );
}
