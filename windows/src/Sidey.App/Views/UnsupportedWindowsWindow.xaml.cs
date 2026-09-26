using Microsoft.UI.Xaml;

using Sidey.App.Localization;
using Sidey.Core.Localization;

namespace Sidey.App.Views;

public sealed partial class UnsupportedWindowsWindow : Window
{
    public UnsupportedWindowsWindow()
    {
        InitializeComponent();
        LocalizationLayout.Apply(UnsupportedRoot);
        Title = I18n.Get("platform.requirements.window_title");
        SideyWindowIcon.Apply(AppWindow);
    }
}
