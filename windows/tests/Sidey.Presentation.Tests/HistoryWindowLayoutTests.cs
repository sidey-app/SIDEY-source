using System.Xml.Linq;

namespace Sidey.Presentation.Tests;

public sealed class HistoryWindowLayoutTests
{
    [Fact]
    public void TimelineKeepsNewestVisibleAndPaginatesAboveMessages()
    {
        DirectoryInfo? root = new(AppContext.BaseDirectory);
        while (root is not null && !Directory.Exists(Path.Combine(root.FullName, "windows", "src")))
        {
            root = root.Parent;
        }

        Assert.NotNull(root);
        var view = XDocument.Load(Path.Combine(
            root!.FullName, "windows", "src", "Sidey.App", "Views", "HistoryWindow.xaml"));
        XElement list = Assert.Single(view.Descendants(), element => element.Name.LocalName == "ListView");
        XElement itemsPanel = Assert.Single(list.Descendants(), element => element.Name.LocalName == "ItemsStackPanel");
        Assert.Equal("KeepLastItemInView", itemsPanel.Attribute("ItemsUpdatingScrollMode")?.Value);

        XElement header = Assert.Single(list.Elements(), element => element.Name.LocalName == "ListView.Header");
        Assert.Contains(header.Descendants(), element =>
            element.Attributes().Any(attribute => attribute.Value.Contains("LoadMoreCommand", StringComparison.Ordinal)));
        Assert.DoesNotContain(list.Elements(), element => element.Name.LocalName == "ListView.Footer");
    }
}
