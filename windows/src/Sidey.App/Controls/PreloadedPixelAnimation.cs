using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace Sidey.App.Controls;

// Every native Image retains its decoded frame. Animation changes only opacity,
// never the image source or a custom composition surface during flight.
public sealed class PreloadedPixelAnimation : Grid
{
    private readonly List<Image> _frames = [];
    private int _frame = -1;

    public PreloadedPixelAnimation() => IsHitTestVisible = false;

    internal void SetFrames(IEnumerable<ImageSource> frames)
    {
        ClearFrames();
        foreach (ImageSource source in frames)
        {
            var image = new Image { Source = source, Stretch = Stretch.None, Opacity = 0 };
            _frames.Add(image);
            Children.Add(image);
        }
    }

    internal void ShowFrame(int frame)
    {
        if (frame == _frame)
            return;
        if (_frame >= 0)
            _frames[_frame].Opacity = 0;
        _frame = frame;
        _frames[frame].Opacity = 1;
    }

    internal void ClearFrames()
    {
        foreach (Image image in _frames)
            image.Source = null;
        Children.Clear();
        _frames.Clear();
        _frame = -1;
    }

}
