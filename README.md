<h1 align="center">Inkplot</h1>

<p align="center">Build clear charts as standalone SVG with plain Ruby data.</p>

<p align="center">
  <a href="https://github.com/rbgfx/inkplot/actions/workflows/main.yml"><img src="https://github.com/rbgfx/inkplot/actions/workflows/main.yml/badge.svg" alt="CI"></a>
  <a href="https://www.ruby-lang.org/"><img src="https://img.shields.io/badge/ruby-%3E%3D3.2-CC342D?logo=ruby&amp;logoColor=white" alt="Ruby 3.2+"></a>
  <a href="LICENSE.txt"><img src="https://img.shields.io/badge/license-MIT-750014.svg" alt="MIT license"></a>
</p>

Inkplot draws line, scatter, bar, area, and step charts without native libraries or runtime dependencies.

## Install

Until the first RubyGems release, add the GitHub repository to your Gemfile:

```ruby
gem "inkplot", github: "rbgfx/inkplot"
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

## Data and output

Charts accept arrays, hashes, CSV tables, and records with string or symbol keys. Scales include linear, logarithmic, and ordered categories. Light and dark themes, grouped and stacked bars, and terminal sparklines are included.

The [gallery](examples/gallery/README.md) contains ten runnable examples. Regenerate its SVG previews with:

```sh
ruby examples/gallery.rb
```

## API contracts

- `to_svg` returns a standalone SVG string; `save` writes an `.svg` file.
- Paired x/y arrays must have the same length. Non-finite y values break line segments by default; use `gaps: :connect` to bridge them.
- Explicit axis limits must be ordered. Log scales omit non-positive values.
- Invalid scales, colors, dimensions, and file extensions raise `ArgumentError`.

## Development

```sh
bundle install
bundle exec rake verify
```

## License

MIT. See [LICENSE.txt](LICENSE.txt).
