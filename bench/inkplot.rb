# frozen_string_literal: true

require "benchmark"
require "inkplot"

points = 1_000.times.map { |index| Math.sin(index / 20.0) }
line = Inkplot.line(points)
scatter = Inkplot.scatter(Array.new(10_000) { |index| index }, Array.new(10_000) { |index| (index * 7_919) % 10_000 })

puts "YJIT=#{RubyVM::YJIT.enabled?} Ruby=#{RUBY_VERSION}"
Benchmark.bm(22) do |bench|
  bench.report("1k line SVG") { line.to_svg }
end

begin
  require "tessel"
  require "glyphic"
  Benchmark.bm(22) do |bench|
    bench.report("1k line PNG") { line.to_png }
    bench.report("10k scatter PNG") { scatter.to_png }
  end
rescue LoadError => e
  warn "PNG benchmarks skipped: #{e.message}"
end
