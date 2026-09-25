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

  it "scales ordered categories" do
    band = Inkplot::Scales::Band.new(%w[b a c], order: %w[a b c])
    band.range = [0, 90]
    expect(band.ticks).to eq(%w[a b c])
    expect([band.map("a"), band.map("c")]).to eq([15, 75])
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
    expect { Inkplot.line([1]).save("chart.png") }.to raise_error(ArgumentError, /\.svg/)
    expect { Inkplot.plot { |plot| plot.hline(Float::INFINITY) } }.to raise_error(ArgumentError, /finite and numeric/)
    expect { Inkplot.plot { |plot| plot.line([1], [2], color: :azure) } }.to raise_error(ArgumentError, /CSS color/)
  end

  it "saves SVG files to the requested path" do
    chart = Inkplot.bar({ "A" => 2, "B" => 4 })
    svg = Tempfile.new(["inkplot", ".svg"])
    chart.save(svg.path)

    expect(REXML::Document.new(File.read(svg.path)).root.name).to eq("svg")
  ensure
    svg&.unlink
  end

  it "builds the ten SVG gallery examples" do
    require_relative "../examples/gallery"

    expect(InkplotGallery.charts.length).to eq(10)
    expect(InkplotGallery.charts.map { |_, chart| REXML::Document.new(chart.to_svg).root.name }.uniq).to eq(["svg"])
  end
end
