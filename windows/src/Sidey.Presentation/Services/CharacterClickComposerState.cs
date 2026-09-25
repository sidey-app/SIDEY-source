namespace Sidey.Presentation.Services;

public enum ComposerVisibilityAction
{
    None,
    Show,
    Hide,
}

public sealed class CharacterClickComposerState
{
    private ComposerVisibilityAction _pendingAction;

    public void BeginSingleClick(bool isVisible) =>
        _pendingAction = isVisible ? ComposerVisibilityAction.Hide : ComposerVisibilityAction.Show;

    public ComposerVisibilityAction CompleteSingleClick()
    {
        ComposerVisibilityAction action = _pendingAction;
        _pendingAction = ComposerVisibilityAction.None;
        return action;
    }

    public void Reset() => _pendingAction = ComposerVisibilityAction.None;
}
