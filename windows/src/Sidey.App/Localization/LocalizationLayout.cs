using Microsoft.UI.Xaml;
using Sidey.Core.Localization;

namespace Sidey.App.Localization;

internal static class LocalizationLayout
{
    public static void Apply(FrameworkElement root)
    {
        root.Language = I18n.Language;
        root.FlowDirection = I18n.IsRightToLeft
            ? FlowDirection.RightToLeft
            : FlowDirection.LeftToRight;
    }
}
