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
      ["10-area", Inkplot.plot(title: "Build time over a release") { |p| p.area((1..8).to_a, [25, 29, 27, 38, 36, 44, 40, 51], label: "Seconds") }],
      ["11-step", Inkplot.plot(title: "Queue depth") { |p| p.step((0..7).to_a, [3, 3, 5, 5, 4, 8, 8, 2], label: "Jobs") }]
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
