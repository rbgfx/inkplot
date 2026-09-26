# frozen_string_literal: true

require "csv"
require "rexml/document"
require "tempfile"

RSpec.describe Inkplot do
  it "maps values to the eight-level sparkline and handles flat or empty data" do
    expect(described_class.sparkline([3, 1, 4, 1, 5, 9])).to eq("▃▁▄▁▅█")
    expect(described_class.sparkline([7, 7, 7])).to eq("▄▄▄")
    expect(described_class.sparkline([nil, Float::NAN])).to eq("")
  end

  it "exposes SVG notebook output and a lazy Inlay adapter" do
    chart = Inkplot.line([1, 3, 2])
    adapter = chart.to_inlay

    expect(chart._repr_svg_).to eq(chart.to_svg)
    expect(adapter[:svg]).to eq(chart.to_svg)
    expect(adapter[:png]).to respond_to(:call)
  end

  it "normalizes numeric vectors, hashes, CSV rows, and mixed record keys" do
    expect(Inkplot::Data.points([2, nil, Float::NAN, 4]).map { |point| point.values_at(:x, :y) }).to eq([[0, 2.0], [1, nil], [2, nil], [3, 4.0]])
    expect(Inkplot::Data.points({ "Ruby" => "42", "Go" => 20 }).map { |point| point.values_at(:x, :y) }).to eq([["Ruby", 42.0], ["Go", 20.0]])
    rows = [{ "date" => "2026-01", :amount => "12", "region" => "north" }, { :date => "2026-02", "amount" => 16, "region" => "south" }]
    expect(Inkplot::Data.points(rows, x: :date, y: "amount").map { |point| point.values_at(:x, :y) }).to eq([["2026-01", 12.0], ["2026-02", 16.0]])
    table = CSV.parse("x,y\na,2\nb,3", headers: true)
    expect(Inkplot::Data.rows(table, x: "x", y: "y").map { |point| point.values_at(:x, :y) }).to eq([["a", 2.0], ["b", 3.0]])
  end

  it "derives nice linear ticks across positive, negative, and narrow ranges" do
    expect(Inkplot::Ticks.linear(0, 1)).to eq([0.0, 0.5, 1.0])
    expect(Inkplot::Ticks.linear(-2, 2)).to eq([-2, -1, 0, 1, 2])
    expect(Inkplot::Ticks.linear(0, 1234)).to eq([0, 500, 1000])
    expect(Inkplot::Scales::Log.new([1, 100]).ticks).to include(1, 10, 100)
    expect(Inkplot::Ticks.linear(0.00012, 0.00078).map { |tick| (tick * 1_000_000).round }).to eq([200, 400, 600])
    expect { Inkplot::Scales::Linear.new([1, 2], min: 4, max: 2) }.to raise_error(ArgumentError, /less than maximum/)
  end

  it "selects second, hour, month, and year time tick labels" do
    second = Inkplot::Scales::Time.new([Time.utc(2026, 1, 1), Time.utc(2026, 1, 1, 0, 1)])
    hour = Inkplot::Scales::Time.new([Time.utc(2026, 1, 1), Time.utc(2026, 1, 1, 6)])
    month = Inkplot::Scales::Time.new([Time.utc(2026, 1, 1), Time.utc(2026, 9, 1)])
    year = Inkplot::Scales::Time.new([Time.utc(2020, 1, 1), Time.utc(2040, 1, 1)])

    expect(second.ticks.map { |tick| second.format(tick) }).to include("00:00:15")
    expect(hour.ticks.map { |tick| hour.format(tick) }).to include("03:00")
    expect(month.ticks.map { |tick| month.format(tick) }).to include("2026-05")
    expect(year.ticks.map { |tick| year.format(tick) }).to include("2030")
  end

  it "scales ordered categories" do
    band = Inkplot::Scales::Band.new(%w[b a c], order: %w[a b c])
    band.range = [0, 90]
    expect(band.ticks).to eq(%w[a b c])
    expect([band.map("a"), band.map("c")]).to eq([15, 75])
  end

  it "estimates ASCII and wide-character text without optional fonts" do
    expect(Inkplot::TextMetrics.width("aあ", 10)).to be_within(0.01).of(15.8)
  end

  it "scales Time and Date values, formats ticks, and rejects mixed UTC offsets" do
    values = [Time.new(2026, 1, 1, 0, 0, 0, "+09:00"), Time.new(2026, 1, 20, 0, 0, 0, "+09:00")]
    scale = Inkplot::Scales::Time.new(values)
    scale.range = [0, 100]

    expect(scale.map(values.first)).to eq(0)
    expect(scale.format(scale.ticks.first)).to match(/2026/)
    expect(Inkplot::Scales::Time.new([Date.new(2026, 1, 1), Date.new(2026, 2, 1)]).ticks).not_to be_empty
    expect(Inkplot.plot { |plot| plot.line(values, [1, 2]) }.to_svg).to include("2026")
    expect { Inkplot::Scales::Time.new([Time.utc(2026), Time.new(2026, 1, 2, 0, 0, 0, "+09:00")]) }.to raise_error(ArgumentError, /same time zone/)
  end

  it "keeps daylight-saving Time values in their shared local zone" do
    previous_timezone = ENV.fetch("TZ", nil)
    ENV["TZ"] = "America/New_York"
    values = [Time.local(2026, 3, 7, 12), Time.local(2026, 3, 9, 12)]

    expect(values.map(&:utc_offset).uniq.length).to eq(2)
    expect(Inkplot::Scales::Time.new(values).ticks).not_to be_empty
  ensure
    ENV["TZ"] = previous_timezone
  end

  it "bins histogram data using fixed edges and Freedman-Diaconis auto sizing" do
    chart = Inkplot.histogram([0, 1, 2, 3, 4], bins: [0, 2, 4])
    points = chart.builder.series.first.points

    expect(points.map { |point| point[:y] }).to eq([2, 3])
    expect(chart.to_svg).to include("histogram-mark")
    expect(Inkplot.histogram([1, 1, 1, 2, 3], bins: :auto).builder.series.first.points.sum { |point| point[:y] }).to eq(5)
    expect(Inkplot.histogram([0, 0, 0, 0, 1_000_000], bins: :auto).builder.series.first.points.length).to eq(4)
    expect { Inkplot.histogram([1, 2], bins: 0) }.to raise_error(ArgumentError, /bins must be/)
    expect { Inkplot.histogram([1, 2], bins: [0, 2, 1]) }.to raise_error(ArgumentError, /strictly increasing/)
  end

  it "creates escaped, valid SVG for line, scatter, step, area, rules, and legend" do
    chart = Inkplot.plot(title: "A <trend>", theme: :dark) do |plot|
      plot.x_axis(label: "Week <1>")
      plot.y_axis(label: "Amount", min: 0)
      plot.line([0, 1, 2, 3], [2, nil, 4, 3], label: "p50", gaps: :break)
      plot.line([0, 1, 2], [1, 2, 1], label: "p99", dash: true)
      plot.scatter([0, 1, 2], [1, 3, 2], label: "samples", size: [1, 2, 3])
      plot.step([0, 1, 2], [3, 2, 4])
      plot.area([0, 1, 2], [0.5, 1, 0.7])
      plot.hline(2.5, label: "SLO")
      plot.vline(1)
    end
    svg = chart.to_svg
    document = REXML::Document.new(svg)

    expect(document.root.attributes["viewBox"]).to eq("0 0 640 360")
    expect(svg).to include("A &lt;trend&gt;", "Week &lt;1&gt;", "series-marks", "stroke-dasharray", "mark-area")
    expect(svg).not_to include("NaN", "Infinity", "href=")
  end

  it "rejects dimensions that cannot fit the axes and legend" do
    narrow = Inkplot.plot(width: 120, height: 100) do |plot|
      plot.line([1, 2], label: "first")
      plot.line([2, 3], label: "second")
    end
    expect { narrow.to_svg }.to raise_error(ArgumentError, /too small for labels or legend/)
  end

  it "uses the dark palette, warns on palette cycling, and omits a single-series legend" do
    expect(Inkplot::Theme.colors(:dark)[:background]).to eq("#171B22")
    expect(Inkplot::Theme.series_color(8, :dark)).not_to eq(Inkplot::Theme::PALETTE.first)
    single = Inkplot.plot { |plot| plot.line([0, 1], [1, 2], label: "only") }.to_svg
    expect(single).not_to include(">only</text>")

    crowded = Inkplot.plot do |plot|
      9.times { |index| plot.line([0, 1], [index, index + 1], label: "series #{index}") }
    end
    expect { crowded.to_svg }.to output(/cycles its eight-color palette/).to_stderr
  end

  it "renders annotation and rule labels and avoids crowded category labels" do
    categories = (1..6).map { |index| "long_category_label_number_#{index}" }
    chart = Inkplot.plot(width: 420, title: "Annotations") do |plot|
      plot.line(categories, [1, 3, 2, 4, 3, 5])
      plot.hline(3, label: "target")
      plot.vline(categories[2], label: "release")
      plot.annotate(categories[4], 4, "note")
    end
    svg = chart.to_svg
    document = REXML::Document.new(svg)
    labels = REXML::XPath.match(document, "//svg:text", { "svg" => "http://www.w3.org/2000/svg" }).map(&:text)

    expect(labels).to include("target", "release", "note")
    expect(svg).to include('transform="rotate(-45')
    expect(labels.count { |label| categories.include?(label) }).to be < categories.length
  end

  it "groups records by color and sorts categories for grouped bars" do
    rows = [
      { month: "Jan", sales: 3, region: "north" },
      { month: "Feb", sales: 5, region: "north" },
      { month: "Jan", sales: 4, region: "south" }
    ]
    line = Inkplot.line(rows, x: :month, y: :sales, color: :region)
    bars = Inkplot.bar({ "Jan" => 3, "Feb" => 5 })

    expect(line.builder.series.map(&:label)).to eq(%w[north south])
    expect(line.builder.series.length).to eq(2)
    expect(bars.to_svg).to include("class=\"bar-mark\"")
    expect(bars.builder.series.first.points.map { |point| point[:x] }).to eq(%w[Jan Feb])
  end

  it "supports horizontal and stacked bars" do
    horizontal = Inkplot.bar({ "Ruby" => 42, "Go" => 20 }, horizontal: true)
    stacked = Inkplot.plot do |plot|
      plot.bar(%w[A B], [2, 3], stacked: true)
      plot.bar(%w[A B], [4, 1], stacked: true)
    end

    expect(horizontal.to_svg).to include("bar-mark")
    expect(stacked.to_svg.scan("<rect ").length).to be >= 5
  end

  it "stacks positive and negative bar values without crossing their baselines" do
    chart = Inkplot.plot do |plot|
      plot.bar(%w[A], [4], stacked: true)
      plot.bar(%w[A], [-2], stacked: true)
      plot.bar(%w[A], [3], stacked: true)
    end
    scene = Inkplot::SceneBuilder.call(chart, width: 640, height: 360)
    bars = scene.marks.select { |mark| mark[:type] == :rect }

    expect(bars.length).to eq(3)
    expect(bars[2][:y] + bars[2][:height]).to be_within(0.01).of(bars[0][:y])
    expect(bars[1][:y]).to be > bars[0][:y]
  end

  it "validates dimensions, vector lengths, output formats, and SVG color input" do
    expect { Inkplot.plot(width: 20) }.to raise_error(ArgumentError, /dimensions/)
    expect { Inkplot.plot { |plot| plot.line([1, 2], [1]) } }.to raise_error(ArgumentError, /same number/)
    expect { Inkplot.plot { |plot| plot.line([1], [2], color: "url(https://example.test)") } }.to raise_error(ArgumentError, /CSS color/)
    expect { Inkplot.line([1]).save("chart.jpg") }.to raise_error(ArgumentError, /\.svg or \.png/)
    expect { Inkplot.plot { |plot| plot.hline(Float::INFINITY) } }.to raise_error(ArgumentError, /finite and numeric/)
    expect { Inkplot.plot { |plot| plot.line([1], [2], color: :azure) } }.to raise_error(ArgumentError, /CSS color/)
    expect { Inkplot.line([1, 2], cap: :square) }.to raise_error(ArgumentError, /line cap/)
    expect { Inkplot.plot { |plot| plot.line([1, 2], [2, 3], width: 0) } }.to raise_error(ArgumentError, /line width/)
  end

  it "saves SVG files to the requested path" do
    chart = Inkplot.bar({ "A" => 2, "B" => 4 })
    svg = Tempfile.new(["inkplot", ".svg"])
    chart.save(svg.path)

    expect(REXML::Document.new(File.read(svg.path)).root.name).to eq("svg")
  ensure
    svg&.unlink
  end

  it "builds twenty valid SVG gallery examples" do
    require_relative "../examples/gallery"

    charts = InkplotGallery.charts
    expect(charts.length).to eq(20)
    expect(charts.map { |_, chart| REXML::Document.new(chart.to_svg).root.name }.uniq).to eq(["svg"])
    charts.each do |name, chart|
      expect(File.read(File.join(__dir__, "../examples/gallery/#{name}.svg"))).to eq(chart.to_svg)
    end
  end
end
