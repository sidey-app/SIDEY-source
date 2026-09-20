namespace Sidey.Presentation.Services;

// A delayed stop from another input must not end the current input's lease.
public sealed class ComposerTypingOwner
{
    private object? _owner;

    public bool? Update(object source, bool active, bool eligible)
    {
        if (active && eligible)
        {
            _owner = source;
            return true;
        }
        if (!ReferenceEquals(_owner, source))
            return null;
        _owner = null;
        return false;
    }
}
