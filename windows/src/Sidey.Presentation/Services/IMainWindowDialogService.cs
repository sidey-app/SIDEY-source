namespace Sidey.Presentation.Services;

public interface IMainWindowDialogService
{
    public Task<bool> ConfirmInviteCodeRotationAsync();

    public Task<string?> PromptForRoomNameAsync(string currentName);

    public Task<bool> ConfirmMemberRemovalAsync(string nickname);

    public Task<bool> ConfirmRoomLeaveAsync(string roomName, bool isOwner);

    public Task<bool> ConfirmRoomDeletionAsync(string roomName);

    public Task<bool> ConfirmSignOutAsync();

    public Task<bool> ConfirmAccountDeletionAsync();

    public Task<bool> ConfirmUpdateDownloadAsync(string version);
}
