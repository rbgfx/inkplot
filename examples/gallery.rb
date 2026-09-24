# frozen_string_literal: true

require "fileutils"
require "inkplot"

module InkplotGallery
  module_function

  def charts
    [
      ["01-line", Inkplot.plot(title: "Weekly signups") do |p|
        p.x_axis(label: "Week")
        p.y_axis(label: "People", min: 0)
        p.line(%w[W1 W2 W3 W4 W5 W6], [18, 25, 21, 36, 43, 58])
      end],
      ["02-line-gaps", Inkplot.plot(title: "Missing values break a line") { |p| p.line((0..7).to_a, [2, 4, nil, 3, 6, Float::NAN, 4, 7], label: "Observed") }],
      ["03-series", Inkplot.plot(title: "Two latency percentiles") do |p|
        p.line((1..6).to_a, [42, 38, 51, 46, 33, 29], label: "p50")
        p.line((1..6).to_a, [92, 108, 115, 97, 82, 76], label: "p99", dash: true)
      end],
      ["04-scatter", Inkplot.plot(title: "Session length and pages") do |p|
        p.scatter([1, 2, 3, 4, 5, 6, 7], [2, 5, 4, 8, 7, 10, 9], size: [1, 4, 2, 6, 3, 8, 5], label: "Sessions")
      end],
      ["05-bars", Inkplot.bar({ "Ruby" => 42, "Rust" => 34, "Go" => 28, "Swift" => 19 }, title: "Repository stars", y_label: "Stars")],
      ["06-horizontal-bars", Inkplot.bar({ "Ruby" => 42, "Rust" => 34, "Go" => 28 }, horizontal: true, title: "Commits by language")],
      ["07-grouped-bars", Inkplot.plot(title: "Quarterly revenue") do |p|
        p.bar(%w[Q1 Q2 Q3 Q4], [18, 23, 28, 36], label: "North")
        p.bar(%w[Q1 Q2 Q3 Q4], [14, 19, 21, 30], label: "South")
      end],
      ["08-stacked-bars", Inkplot.plot(title: "Traffic by channel") do |p|
        p.bar(%w[Mon Tue Wed Thu Fri], [12, 16, 11, 19, 22], label: "Direct", stacked: true)
        p.bar(%w[Mon Tue Wed Thu Fri], [8, 9, 13, 10, 14], label: "Search", stacked: true)
      end],
      ["09-signed-stack", Inkplot.plot(title: "Daily net change") do |p|
        p.bar(%w[Mon Tue Wed Thu Fri], [8, -4, 5, -2, 9], label: "New", stacked: true)
        p.bar(%w[Mon Tue Wed Thu Fri], [3, -6, 2, -5, 4], label: "Removed", stacked: true)
      end],
      ["10-area", Inkplot.plot(title: "Build time over a release") { |p| p.area((1..8).to_a, [25, 29, 27, 38, 36, 44, 40, 51], label: "Seconds") }],
      ["11-step", Inkplot.plot(title: "Queue depth") { |p| p.step((0..7).to_a, [3, 3, 5, 5, 4, 8, 8, 2], label: "Jobs") }],
      ["12-histogram", Inkplot.histogram([8, 9, 10, 10, 11, 12, 12, 13, 14, 15, 17, 18, 22, 25, 31, 33], bins: :auto, title: "Response time", x_label: "Milliseconds")],
      ["13-log-scale", Inkplot.plot(title: "Growth on a log scale") do |p|
        p.y_axis(scale: :log, min: 1)
        p.line((0..5).to_a, [1, 3, 9, 27, 81, 243])
      end],
      ["14-time-axis", Inkplot.plot(title: "Hourly requests") do |p|
        p.x_axis(label: "UTC", type: :time)
        p.line((0..6).map do |hour|
          Time.utc(2026, 9, 24, hour * 4)
        end, [12, 17, 15, 24, 31, 27, 38])
      end],
      ["15-category-order", Inkplot.plot(title: "Deployment health") do |p|
        p.x_axis(order: %w[dev staging production])
        p.line(%w[production dev staging], [98, 100, 99], label: "Success %")
      end],
      ["16-dark-theme", Inkplot.plot(title: "Dark dashboard", theme: :dark) do |p|
        p.line((1..7).to_a, [12, 18, 16, 24, 22, 30, 35], label: "Throughput")
        p.hline(20, label: "Target", color: :orange)
      end],
      ["17-annotations", Inkplot.plot(title: "Service level objective") do |p|
        p.line((1..7).to_a, [32, 28, 41, 36, 30, 24, 27])
        p.hline(35, label: "SLO", color: :red)
        p.vline(4, color: :blue)
        p.text(4.1, 42, "deploy")
      end],
      ["18-combo", Inkplot.plot(title: "Sales and conversion") do |p|
        p.bar(%w[Jan Feb Mar Apr], [24, 30, 27, 42], label: "Orders")
        p.line(%w[Jan Feb Mar Apr], [2.8, 3.1, 3.0, 3.8], label: "Conversion %", color: :red)
      end],
      ["19-legend-position", Inkplot.plot(title: "Legend below", width: 640, height: 380) do |p|
        p.line((1..5).to_a, [3, 5, 4, 7, 6], label: "Actual")
        p.line((1..5).to_a, [2, 3, 4, 5, 6], label: "Plan")
        p.legend(position: :bottom_left)
      end],
      ["20-long-categories", Inkplot.plot(title: "Labels rotate when needed") do |p|
        p.x_axis(order: ["North America", "South America", "Europe", "Asia Pacific"])
        p.bar(["North America", "South America", "Europe", "Asia Pacific"], [22, 14, 31, 27])
      end]
    ]
  end
end

if $PROGRAM_NAME == __FILE__
  update_snapshots = ARGV.delete("--update-snapshots")
  raise ArgumentError, "usage: ruby examples/gallery.rb [--update-snapshots]" unless ARGV.empty?

  svg_dir = File.expand_path("gallery", __dir__)
  FileUtils.mkdir_p(svg_dir)

  InkplotGallery.charts.each do |name, chart|
    File.write(File.join(svg_dir, "#{name}.svg"), chart.to_svg)
    next unless update_snapshots

    require "tessel"
    require "glyphic"
    png_dir = File.expand_path("../spec/snapshots", __dir__)
    FileUtils.mkdir_p(png_dir)
    File.binwrite(File.join(png_dir, "#{name}.png"), Tessel::PNG.encode(chart.to_image))
  end
end
