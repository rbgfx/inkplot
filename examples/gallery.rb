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
      ["09-histogram", Inkplot.histogram([12, 14, 15, 15, 16, 18, 19, 20, 22, 24, 25, 31, 35, 42], title: "Request latency", bins: :auto, x_label: "ms")],
      ["10-area", Inkplot.plot(title: "Build time over a release") { |p| p.area((1..8).to_a, [25, 29, 27, 38, 36, 44, 40, 51], label: "Seconds") }],
      ["11-step", Inkplot.plot(title: "Queue depth") { |p| p.step((0..7).to_a, [3, 3, 5, 5, 4, 8, 8, 2], label: "Jobs") }],
      ["12-time", Inkplot.plot(title: "Monthly active users") do |p|
        p.x_axis(label: "Month", type: :time)
        p.line((0..11).map { |month| Time.utc(2026, month + 1, 1) }, [34, 37, 36, 42, 48, 51, 49, 57, 62, 66, 72, 79], label: "Users")
      end],
      ["13-annotations", Inkplot.plot(title: "Release performance") do |p|
        p.line(%w[v1.0 v1.1 v1.2 v1.3], [34, 42, 39, 55], label: "Requests/s")
        p.hline(45, label: "Target", color: "#D55E00")
        p.vline("v1.2", label: "Cache enabled", color: "#0072B2")
        p.annotate("v1.3", 55, "peak", anchor: :end)
      end],
      ["14-dark-theme", Inkplot.plot(title: "Dark theme", theme: :dark) do |p|
        p.line(%w[Mon Tue Wed Thu Fri], [12, 16, 14, 22, 19], label: "Deploys")
        p.line(%w[Mon Tue Wed Thu Fri], [8, 9, 13, 12, 18], label: "Rollbacks")
      end],
      ["15-category-labels", Inkplot.bar((1..18).to_h { |index| ["Region #{index} very long", ((index * 7) % 31) + 4] }, title: "Regional volume")],
      ["16-custom-bins", Inkplot.histogram([2, 4, 5, 7, 9, 11, 14, 18, 21, 24, 28, 35], bins: [0, 10, 20, 30, 40], title: "Custom latency ranges")],
      ["17-connected-gaps", Inkplot.plot(title: "Bridge short gaps") do |p|
        p.line((0..8).to_a, [2, 3, nil, 5, 6, nil, 4, 7, 8], label: "Estimated", gaps: :connect)
      end],
      ["18-step-series", Inkplot.plot(title: "Rate limit changes") do |p|
        p.step((0..6).to_a, [50, 50, 75, 75, 100, 100, 125], label: "Requests/min")
        p.hline(100, label: "Current limit")
      end],
      ["19-combined-marks", Inkplot.plot(title: "Quarterly sales") do |p|
        p.bar(%w[Q1 Q2 Q3 Q4], [16, 20, 18, 27], label: "Previous")
        p.line(%w[Q1 Q2 Q3 Q4], [19, 25, 24, 34], label: "Current")
      end],
      ["20-scatter-sizes", Inkplot.plot(title: "Session length vs. pages") do |p|
        p.scatter([12, 18, 21, 27, 32, 38, 44], [2, 3, 5, 4, 7, 8, 10], size: [1, 2, 3, 2, 5, 6, 8], label: "Sessions")
        p.annotate(38, 8, "engaged")
      end]
    ]
  end
end

if $PROGRAM_NAME == __FILE__
  raise ArgumentError, "usage: ruby examples/gallery.rb" unless ARGV.empty?

  svg_dir = File.expand_path("gallery", __dir__)
  FileUtils.mkdir_p(svg_dir)

  InkplotGallery.charts.each do |name, chart|
    File.write(File.join(svg_dir, "#{name}.svg"), chart.to_svg)
  end
end
