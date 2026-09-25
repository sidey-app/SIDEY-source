using Sidey.Presentation.Services;

namespace Sidey.Presentation.Tests;

public sealed class CharacterClickComposerStateTests
{
    [Theory]
    [InlineData(false, ComposerVisibilityAction.Show)]
    [InlineData(true, ComposerVisibilityAction.Hide)]
    public void SingleClickTogglesOnlyWhenTheClickWindowExpires(
        bool initiallyVisible,
        ComposerVisibilityAction expectedAction)
    {
        var state = new CharacterClickComposerState();

        state.BeginSingleClick(initiallyVisible);
        Assert.Equal(expectedAction, state.CompleteSingleClick());
        Assert.Equal(ComposerVisibilityAction.None, state.CompleteSingleClick());
    }

    [Fact]
    public void DoubleClickOrAnotherVisibilityChangeCancelsThePendingToggle()
    {
        var state = new CharacterClickComposerState();

        state.BeginSingleClick(isVisible: false);
        state.Reset();
        Assert.Equal(ComposerVisibilityAction.None, state.CompleteSingleClick());

        state.BeginSingleClick(isVisible: true);
        Assert.Equal(ComposerVisibilityAction.Hide, state.CompleteSingleClick());
    }
}
