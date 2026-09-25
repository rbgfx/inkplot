# frozen_string_literal: true

require_relative "inkplot/version"
require_relative "inkplot/core"
require_relative "inkplot/renderers/svg"
require_relative "inkplot/renderers/png"

module Inkplot
  class Error < StandardError; end

  class Config
    attr_accessor :font
  end

  Series = Struct.new(:type, :points, :label, :color, :options, keyword_init: true)
  Scene = Struct.new(:width, :height, :background, :clip, :marks, :elements, keyword_init: true)

  class << self
    def config = @config ||= Config.new

    def plot(width: 640, height: 360, theme: :light, **)
      builder = Builder.new(width: width, height: height, theme: theme, **)
      yield builder if block_given?
      Chart.new(builder)
    end

    def line(data, values = nil, x: nil, y: nil, color: nil, title: nil, x_label: nil, y_label: nil, **)
      quick(:line, data, values, x:, y:, color:, title:, x_label:, y_label:, **)
    end

    def scatter(data, values = nil, x: nil, y: nil, size: nil, color: nil, title: nil, x_label: nil, y_label: nil, **)
      quick(:scatter, data, values, x:, y:, size:, color:, title:, x_label:, y_label:, **)
    end

    def bar(data, horizontal: false, title: nil, x_label: nil, y_label: nil, **options)
      chart_options, mark_options = options.partition { |key, _| %i[width height theme].include?(key) }.map(&:to_h)
      builder = Builder.new(**chart_options, title:, x_label:, y_label:)
      if horizontal
        builder.bar(data, horizontal: true, **mark_options)
      else
        builder.bar(data, **mark_options)
      end
      Chart.new(builder)
    end

    def histogram(data, bins: :auto, title: nil, x_label: nil, y_label: nil, **options)
      chart_options, mark_options = options.partition { |key, _| %i[width height theme].include?(key) }.map(&:to_h)
      builder = Builder.new(**chart_options, title:, x_label:, y_label:)
      builder.histogram(data, bins:, **mark_options)
      Chart.new(builder)
    end

    def sparkline(values)
      values = values.filter_map { |value| Data.number(value) }
      return "" if values.empty?

      low, high = values.minmax
      glyphs = "▁▂▃▄▅▆▇█"
      return glyphs[3] * values.length if low == high

      values.map { |value| glyphs[((value - low) / (high - low) * 7).round] }.join
    end

    private

    def quick(type, data, values = nil, x:, y:, size: nil, color: nil, title: nil, x_label: nil, y_label: nil, **options)
      chart_options, mark_options = options.partition { |key, _| %i[width height theme].include?(key) }.map(&:to_h)
      builder = Builder.new(**chart_options, title:, x_label:, y_label:)
      if color && Data.records?(data)
        Data.rows(data, x:, y:, size:, group: color).group_by { |point| point[:group] }.each do |group, points|
          builder.add(type, points, label: group.to_s, **mark_options)
        end
      else
        builder.add(type, Data.points(data, values, x:, y:, size:), **mark_options)
      end
      Chart.new(builder)
    end
  end
end
