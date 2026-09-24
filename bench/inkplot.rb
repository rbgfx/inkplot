# frozen_string_literal: true

require "benchmark"
require "inkplot"

points = 1_000.times.map { |index| Math.sin(index / 20.0) }
line = Inkplot.line(points)
scatter = Inkplot.scatter(10_000.times.map { |index| [index % 1_000, Math.sin(index / 100.0)] })

puts "YJIT=#{RubyVM::YJIT.enabled?} Ruby=#{RUBY_VERSION}"
Benchmark.bm(22) do |bench|
  bench.report("1k line SVG") { line.to_svg }
  bench.report("1k line PNG") { line.to_png }
  bench.report("10k scatter PNG") { scatter.to_png }
end
