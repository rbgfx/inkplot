# frozen_string_literal: true

require "csv"
require "rexml/document"
require "tempfile"
require "lookalike"

Lookalike.config.snapshot_dir = File.expand_path("snapshots", __dir__)

RSpec.describe Inkplot do
  it "maps values to the eight-level sparkline and handles flat or empty data" do
    expect(described_class.sparkline([3, 1, 4, 1, 5, 9])).to eq("▃▁▄▁▅█")
    expect(described_class.sparkline([7, 7, 7])).to eq("▄▄▄")
    expect(described_class.sparkline([nil, Float::NAN])).to eq("")
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
    expect { Inkplot::Scales::Linear.new([1, 2], min: 4, max: 2) }.to raise_error(ArgumentError, /less than maximum/)
  end

  it "scales ordered categories and time values while rejecting mixed offsets" do
    band = Inkplot::Scales::Band.new(%w[b a c], order: %w[a b c])
    band.range = [0, 90]
    expect(band.ticks).to eq(%w[a b c])
    expect([band.map("a"), band.map("c")]).to eq([15, 75])
    expect(Inkplot::Ticks.time_label(Time.utc(2026, 9, 1).to_f, 400 * 86_400, offset: 0)).to eq("2026")
    expect do
      Inkplot::Scales::TimeScale.new([Time.utc(2026), Time.new(2026, 1, 2, 0, 0, 0, "+01:00")])
    end.to raise_error(ArgumentError, /mixed UTC offsets/)
  end

  it "thins crowded category labels while retaining the endpoints" do
    categories = (1..40).map { |index| "Category #{index}" }
    chart = Inkplot.plot(width: 320, height: 220) do |plot|
      plot.bar(categories, (1..40).to_a)
    end
    labels = Inkplot::SceneBuilder.call(chart, width: 320, height: 220).elements
                                  .select { |element| element[:type] == :text && element[:text].start_with?("Category") }
                                  .map { |element| element[:text] }

    expect(labels.length).to be < categories.length
    expect(labels).to include(categories.first, categories.last)
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
      plot.text(2, 3, "note & mark")
    end
    svg = chart.to_svg
    document = REXML::Document.new(svg)

    expect(document.root.attributes["viewBox"]).to eq("0 0 640 360")
    expect(svg).to include("A &lt;trend&gt;", "Week &lt;1&gt;", "series-marks", "stroke-dasharray", "mark-area", "note &amp; mark")
    expect(svg).not_to include("NaN", "Infinity", "href=")
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

  it "supports horizontal and stacked bars, histogram bins, and annotations" do
    horizontal = Inkplot.bar({ "Ruby" => 42, "Go" => 20 }, horizontal: true)
    histogram = Inkplot.histogram([0, 1, 2, 3, 4, 5], bins: 3, x_label: "ms")
    stacked = Inkplot.plot do |plot|
      plot.bar(%w[A B], [2, 3], stacked: true)
      plot.bar(%w[A B], [4, 1], stacked: true)
    end

    expect(horizontal.to_svg).to include("bar-mark")
    expect(histogram.to_svg.scan("<rect ").length).to be >= 4
    expect(stacked.to_svg.scan("<rect ").length).to be >= 5
    expect { Inkplot.histogram([]) }.to raise_error(ArgumentError, /at least one/)
    expect { Inkplot.histogram([1, 2], bins: 0) }.to raise_error(ArgumentError, /bins must/)
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

  it "uses the Time scale and emits compact, correctly formatted labels" do
    times = [Time.utc(2026, 1, 1), Time.utc(2026, 1, 2), Time.utc(2026, 1, 3)]
    chart = Inkplot.plot do |plot|
      plot.x_axis(type: :time)
      plot.line(times, [1, 3, 2])
    end

    expect(chart.to_svg).to include("2026")
    expect(Inkplot::Ticks.number_label(0.30000000000000004)).to eq("0.3")
  end

  it "validates dimensions, vector lengths, output formats, and SVG color input" do
    expect { Inkplot.plot(width: 20) }.to raise_error(ArgumentError, /dimensions/)
    expect { Inkplot.plot { |plot| plot.line([1, 2], [1]) } }.to raise_error(ArgumentError, /same number/)
    expect { Inkplot.plot { |plot| plot.line([1], [2], color: "url(https://example.test)") } }.to raise_error(ArgumentError, /CSS color/)
    expect { Inkplot.line([1]).save("chart.jpg") }.to raise_error(ArgumentError, /\.svg or \.png/)
    expect { Inkplot.plot { |plot| plot.hline(Float::INFINITY) } }.to raise_error(ArgumentError, /finite and numeric/)
    expect { Inkplot.plot { |plot| plot.line([1], [2], color: :azure) } }.to raise_error(ArgumentError, /CSS color/)
  end

  it "renders PNG with optional Tessel and Glyphic, supports scale, and adapts to Inlay" do
    chart = Inkplot.line([0, 1, 2], [2, 4, 3], title: "Raster")
    image = chart.to_image(scale: 2)
    payload = chart.to_inlay
    decoded = Tessel.decode(chart.to_png)

    expect([image.width, image.height]).to eq([1280, 720])
    expect([decoded.width, decoded.height]).to eq([640, 360])
    expect(payload[:svg]).to start_with("<?xml")
    expect(Tessel.decode(payload[:png].call).width).to eq(640)
  end

  it "fills raster paths with the non-zero rule and clips to image bounds" do
    image = Tessel::Image.new(4, 4, fill: [255, 255, 255, 255])
    Inkplot::Renderers::Raster::PathFiller.fill(image, [[0, 0], [2, 0], [2, 2], [0, 2]], [255, 0, 0, 255])

    expect((0...2).flat_map { |y| (0...2).map { |x| image[x, y] } }).to all(eq([255, 0, 0, 255]))
    expect(image[3, 3]).to eq([255, 255, 255, 255])
  end

  it "saves SVG and PNG files to the requested paths" do
    chart = Inkplot.bar({ "A" => 2, "B" => 4 })
    svg = Tempfile.new(["inkplot", ".svg"])
    png = Tempfile.new(["inkplot", ".png"])
    chart.save(svg.path)
    chart.save(png.path)

    expect(REXML::Document.new(File.read(svg.path)).root.name).to eq("svg")
    expect(Tessel.decode(File.binread(png.path)).width).to eq(640)
  ensure
    svg&.unlink
    png&.unlink
  end

  it "matches the 20-chart gallery PNG snapshots" do
    require_relative "../examples/gallery"

    InkplotGallery.charts.each do |name, chart|
      expected = File.join(__dir__, "snapshots", "#{name}.png")
      result = Lookalike.compare(expected, chart.to_image, mode: :channel)
      expect(result.match?).to be(true), "gallery snapshot changed: #{name}"
    end
  end
end
