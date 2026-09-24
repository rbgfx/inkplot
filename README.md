<h1 align="center">Inkplot</h1>

<p align="center">Ruby charts, drawn as portable SVG or PNG.</p>

<p align="center">
  <a href="https://github.com/rbgfx/inkplot/actions/workflows/main.yml"><img src="https://github.com/rbgfx/inkplot/actions/workflows/main.yml/badge.svg" alt="CI"></a>
  <a href="https://www.ruby-lang.org/"><img src="https://img.shields.io/badge/ruby-%3E%3D3.2-CC342D?logo=ruby&amp;logoColor=white" alt="Ruby 3.2+"></a>
  <a href="LICENSE.txt"><img src="https://img.shields.io/badge/license-MIT-750014.svg" alt="MIT license"></a>
</p>

Line, bar, scatter, area, step, and histogram charts with clean defaults. SVG runs on Ruby alone; optional pure Ruby image gems add PNG output and REPL display.

## At a glance

- **No runtime dependencies for SVG** and no native graphics libraries.
- **Useful defaults:** automatic linear, logarithmic, category, and time scales; readable ticks, legends, and light or dark themes.
- **Ruby data in:** arrays, hashes, CSV tables, and records with string or symbol keys.
- **Flexible output:** SVG strings, PNG bytes, `Tessel::Image`, files, and terminal sparklines.
- **Optional adapters:** Tessel and Glyphic for PNG; Inlay for IRB, Pry, and IRuby.

## Install

Until the first RubyGems release, add Inkplot from GitHub:

```ruby
gem "inkplot", github: "rbgfx/inkplot"
```

SVG needs only Inkplot. For PNG output, add the optional render dependencies:

```ruby
gem "tessel", github: "rbgfx/tessel"
gem "glyphic", github: "rbgfx/glyphic"
```

Glyphic's built-in font covers ASCII. For other scripts, set a TrueType font:

```ruby
Inkplot.config.font = "/path/to/font.ttf"
```

## Quick start

```ruby
require "inkplot"

chart = Inkplot.line([3, 1, 4, 1, 5, 9, 2, 6], title: "A small series")
chart.save("series.svg")
chart.save("series.png", width: 800, height: 450, scale: 2)
```

Use CSV or records directly. Keys can be symbols or strings; `color:` splits records into labeled series.

```ruby
require "csv"

rows = CSV.parse(File.read("sales.csv"), headers: true)
chart = Inkplot.line(rows, x: "month", y: "sales", color: "region", title: "Monthly sales")
chart.to_svg # => standalone SVG string
```

The builder API combines marks, scales, and annotations:

```ruby
chart = Inkplot.plot(width: 720, height: 420, theme: :dark) do |plot|
  plot.title "Request latency"
  plot.x_axis label: "Time", type: :time
  plot.y_axis label: "Milliseconds", scale: :log, min: 1
  plot.line times, p50, label: "p50"
  plot.line times, p99, label: "p99", dash: true
  plot.hline 200, label: "SLO", color: :red
  plot.legend position: :top_right
end
```

`Inkplot.bar(data, horizontal: true)` draws horizontal bars. `Inkplot.histogram(values, bins: :auto)` chooses bins with Freedman–Diaconis, falling back to Sturges when the interquartile range is zero. Builder methods also provide grouped and signed stacked bars, areas, steps, sized scatter points, and text or line annotations.

## Gallery

Twenty runnable chart examples and SVG previews are in the [gallery](examples/gallery/README.md). Rebuild the SVGs with:

```sh
ruby examples/gallery.rb
```

## REPL and terminal

When [Inlay](https://github.com/rbgfx/inlay) is loaded, Inkplot's `to_inlay` adapter returns SVG plus a lazy PNG fallback. A terminal without an inline image protocol can use:

```ruby
puts Inkplot.sparkline([3, 1, 4, 1, 5, 9, 2, 6]) # => "▃▁▄▁▅█▂▅"
```

## Performance

Reference run on Ruby 4.0.6 with YJIT, at 640×360: a 1,000-point line rendered to SVG in 3 ms, the same chart to PNG in 235 ms, and a 10,000-point scatter plot to PNG in 668 ms. These single-run measurements met the design targets of 50 ms, 300 ms, and 1 second respectively; see `bench/inkplot.rb` to rerun them.

## API contracts

- Chart dimensions must be at least 120×100 pixels. Paired x/y vectors must have equal lengths.
- Non-finite y values are treated as gaps. `gaps: :connect` connects line segments across them.
- Explicit axis limits must be valid and ordered. Log axes omit non-positive values with a warning; mixed time-zone offsets raise `ArgumentError`.
- Invalid scales, colors, dimensions, bin definitions, and output extensions raise `ArgumentError`.
- `to_svg` needs no optional gems. PNG methods raise `LoadError` with the missing gem's install command.
- SVG text is escaped; color input accepts a hexadecimal value or a supported CSS color name.
- PNG rendering uses a built-in 2× coverage pass before downsampling. Pure Ruby rendering is intended for charts and reports, not huge photo workloads.

## Development

```sh
bundle install
bundle exec rake verify
bundle exec rbs validate
```

The test suite compares all gallery PNGs against Lookalike snapshots. Update them intentionally with `bundle exec ruby examples/gallery.rb --update-snapshots`.

## License

[MIT](LICENSE.txt)
