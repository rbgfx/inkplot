# frozen_string_literal: true

require "benchmark"
require "inkplot"

points = 1_000.times.map { |index| Math.sin(index / 20.0) }
line = Inkplot.line(points)

puts "YJIT=#{RubyVM::YJIT.enabled?} Ruby=#{RUBY_VERSION}"
Benchmark.bm(22) do |bench|
  bench.report("1k line SVG") { line.to_svg }
end
