<h1 align="center">Inkplot</h1>

<p align="center">Build clear SVG and PNG charts from plain Ruby data.</p>

<p align="center">
  <a href="https://github.com/rbgfx/inkplot/actions/workflows/main.yml"><img src="https://github.com/rbgfx/inkplot/actions/workflows/main.yml/badge.svg" alt="CI"></a>
  <a href="https://www.ruby-lang.org/"><img src="https://img.shields.io/badge/ruby-%3E%3D3.2-CC342D?logo=ruby&amp;logoColor=white" alt="Ruby 3.2+"></a>
  <a href="LICENSE.txt"><img src="https://img.shields.io/badge/license-MIT-750014.svg" alt="MIT license"></a>
</p>

Inkplot draws line, scatter, bar, area, histogram, and step charts without runtime dependencies. SVG output uses only Ruby's standard library; optional PNG output needs `tessel` and `glyphic`.

## Install

Install the gem:

```sh
gem install inkplot
```

## Quick start

```ruby
require "inkplot"

chart = Inkplot.line([3, 1, 4, 1, 5, 9], title: "A small series")
chart.save("series.svg")
```

Use the builder to combine series and configure axes:

```ruby
chart = Inkplot.plot(width: 720, height: 420, theme: :dark) do |plot|
  plot.title "Quarterly requests"
  plot.x_axis(label: "Quarter")
  plot.y_axis(label: "Requests", min: 0)
  plot.line(%w[Q1 Q2 Q3 Q4], [18, 23, 28, 36], label: "Current")
  plot.line(%w[Q1 Q2 Q3 Q4], [14, 19, 21, 30], label: "Previous", dash: true)
  plot.hline(25, label: "Target")
  plot.legend(position: :top_right)
end

svg = chart.to_svg
```

## PNG output

PNG rendering is optional and uses the pure Ruby [Tessel](https://github.com/rbgfx/tessel) and [Glyphic](https://github.com/rbgfx/glyphic) gems:

```sh
gem install tessel glyphic
```

```ruby
chart = Inkplot.line([3, 1, 4, 1, 5, 9], title: "A small series")
chart.save("series.png", scale: 2)
png_bytes = chart.to_png
```

Set `Inkplot.config.font` to a TrueType font path for Unicode text. Without a font path, PNG output uses Glyphic's small ASCII bitmap font; SVG uses the viewer's system fonts.

## Data and output

Charts accept arrays, hashes, CSV tables, and records with string or symbol keys. Scales include linear, logarithmic, time (`Time` and `Date`), and ordered categories. Light and dark themes, grouped and stacked bars, annotations, and terminal sparklines are included.

```ruby
latencies = [12, 13, 15, 15, 18, 21, 26, 42]
Inkplot.histogram(latencies, bins: :auto, x_label: "ms").save("latencies.svg")
```

For dated data, configure the x axis with `type: :time`. `plot.annotate(x, y, "text")` places text at a data point; `hline` and `vline` can also carry labels.

The [gallery](examples/gallery/README.md) contains 20 runnable examples. Regenerate its SVG previews with:

```sh
ruby examples/gallery.rb
```

## API contracts

- `to_svg` returns a standalone SVG string; `save` writes `.svg` or `.png` files. `to_png` returns PNG bytes and `to_image` returns a `Tessel::Image`.
- Paired x/y arrays must have the same length. Non-finite y values break line segments by default; use `gaps: :connect` to bridge them.
- Explicit axis limits must be ordered. Log scales omit non-positive values. Time axes reject mixed time zones while preserving local daylight-saving transitions.
- Invalid scales, colors, dimensions, and file extensions raise `ArgumentError`.
- Charts provide `_repr_svg_` for notebook frontends and `to_inlay` for [Inlay](https://github.com/rbgfx/inlay); neither is a runtime dependency.

## Development

```sh
bundle install
bundle exec rake verify
```

## License

MIT. See [LICENSE.txt](LICENSE.txt).
