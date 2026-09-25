namespace Sidey.Presentation.Services;

public enum ComposerVisibilityAction
{
    None,
    Show,
    Hide,
}

public sealed class CharacterClickComposerState
{
    private bool? _initialVisibility;
    private bool _feedbackApplied;

    public void BeginSingleClick(bool isVisible)
    {
        _initialVisibility = isVisible;
        _feedbackApplied = false;
    }

    public ComposerVisibilityAction CompleteSingleClick()
    {
        if (_initialVisibility is not { } wasVisible || _feedbackApplied)
        {
            return ComposerVisibilityAction.None;
        }

        _feedbackApplied = true;
        return wasVisible ? ComposerVisibilityAction.Hide : ComposerVisibilityAction.Show;
    }

    public ComposerVisibilityAction CompleteDoubleClick()
    {
        ComposerVisibilityAction action = ComposerVisibilityAction.None;
        if (_feedbackApplied && _initialVisibility is { } wasVisible)
        {
            action = wasVisible ? ComposerVisibilityAction.Show : ComposerVisibilityAction.Hide;
        }

        Reset();
        return action;
    }

    public void Reset()
    {
        _initialVisibility = null;
        _feedbackApplied = false;
    }
}
