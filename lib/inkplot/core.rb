# frozen_string_literal: true

module Inkplot
  module Data
    module_function

    def number(value)
      return nil if value.nil?
      return value.to_f if value.is_a?(Numeric) && value.to_f.finite?

      Float(value, exception: false)&.then { |number| number.finite? ? number : nil }
    rescue RangeError
      nil
    end

    def points(data, values = nil, x: nil, y: nil, size: nil)
      if values
        xs = Array(data)
        ys = Array(values)
        raise ArgumentError, "x and y must have the same number of values" unless xs.length == ys.length

        sizes = size.is_a?(Array) ? size : Array.new(xs.length, size)
        return xs.each_index.map { |index| { x: xs[index], y: number(ys[index]), size: number(sizes[index]) } }
      end
      if data.is_a?(Hash) && x && y
        x_values = value(data, x)
        y_values = value(data, y)
        return points(x_values, y_values, size: size && value(data, size)) if x_values && y_values
      end
      return data.map { |key, value| { x: key, y: number(value) } } if data.is_a?(Hash)
      return rows(data, x:, y:, size:) if records?(data)
      return data.map { |x_value, y_value| { x: x_value, y: number(y_value) } } if data.is_a?(Array) && data.first.is_a?(Array) && data.first.length == 2

      Array(data).each_with_index.map { |value, index| { x: index, y: number(value) } }
    end

    def records?(data)
      first = data.first if data.is_a?(Array)
      first&.then { |row| row.is_a?(Hash) || (row.respond_to?(:to_h) && !row.is_a?(Array)) } || (data.respond_to?(:headers) && data.respond_to?(:each))
    end

    def rows(data, x: nil, y: nil, size: nil, group: nil)
      source = data.respond_to?(:headers) && data.respond_to?(:each) ? data : Array(data)
      source.map do |row|
        record = row.respond_to?(:to_h) ? row.to_h : row
        x_key = x || record.keys[0]
        y_key = y || record.keys[1]
        { x: value(record, x_key), y: number(value(record, y_key)), size: number(value(record, size)), group: value(record, group) }
      end
    end

    def value(record, key)
      return nil if key.nil?
      return record[key] if record.key?(key)

      alternate = key.is_a?(Symbol) ? key.to_s : key.to_sym
      record[alternate]
    rescue NoMethodError
      nil
    end
  end

  module Ticks
    module_function

    def linear(minimum, maximum, count: 5)
      return [minimum] if minimum >= maximum

      step = linear_step(minimum, maximum, count:)
      first = (minimum / step).ceil * step
      last = (maximum / step).floor * step
      ticks = []
      value = first
      while value <= last + (step * 1e-10) && ticks.length < 1000
        ticks << ((value / step).round(10) * step)
        value += step
      end
      ticks.empty? ? [minimum, maximum].uniq : ticks
    end

    def linear_step(minimum, maximum, count: 5)
      return 1.0 unless maximum > minimum

      raw = (maximum - minimum).to_f / [count - 1, 1].max
      power = 10.0**Math.log10(raw).floor
      fraction = raw / power
      (if fraction <= 1
         1
       elsif fraction <= 2
         2
       else
         fraction <= 5 ? 5 : 10
       end) * power
    end

    def log(minimum, maximum)
      low = Math.log10(minimum).floor
      high = Math.log10(maximum).ceil
      exponents = (low..high).to_a
      if high - low <= 2
        exponents.flat_map { |power| [1, 2, 5].map { |multiple| multiple * (10.0**power) } }.grep(minimum..maximum)
      else
        exponents.map { |power| 10.0**power }.grep(minimum..maximum)
      end
    end

    def number_label(value)
      value.to_i == value ? value.to_i.to_s : format("%.8f", value).sub(/0+\z/, "").sub(/\.\z/, "")
    end
  end

  module Scales
    class Linear
      attr_reader :domain, :ticks
      attr_accessor :range

      def initialize(values, options = {}, include_zero: false, **axis_options)
        options = options.merge(axis_options)
        values = values.filter_map { |value| Data.number(value) }
        low, high = values.minmax
        low ||= 0.0
        high ||= 1.0
        low = [low, 0.0].min if include_zero
        high = [high, 0.0].max if include_zero
        low = limit(options[:min], low, "minimum")
        high = limit(options[:max], high, "maximum")
        if low == high
          raise ArgumentError, "linear axis minimum must be less than maximum" if options[:min] && options[:max]

          low -= low.zero? ? 1 : low.abs * 0.1 if options[:min].nil?
          high += high.zero? ? 1 : high.abs * 0.1 if options[:max].nil?
        end
        raise ArgumentError, "linear axis minimum must be less than maximum" unless low < high

        @ticks = Ticks.linear(low, high)
        step = Ticks.linear_step(low, high)
        low = (low / step).floor * step if options[:min].nil?
        high = (high / step).ceil * step if options[:max].nil?
        @domain = [low, high]
      end

      def map(value)
        value = Data.number(value)
        return nil unless value

        @range[0] + ((value - @domain[0]) * (@range[1] - @range[0]) / (@domain[1] - @domain[0]))
      end

      def format(value) = Ticks.number_label(value)

      private

      def limit(value, fallback, name)
        return fallback if value.nil?

        number = Data.number(value)
        raise ArgumentError, "linear axis #{name} must be numeric" unless number

        number
      end
    end

    class Log
      attr_reader :domain, :ticks
      attr_accessor :range

      def initialize(values, options = {})
        positive = values.filter_map { |value| Data.number(value) }.select(&:positive?)
        low, high = positive.minmax
        low ||= 1.0
        high ||= 10.0
        low = axis_limit(options[:min], low, "minimum")
        high = axis_limit(options[:max], high, "maximum")
        raise ArgumentError, "log axis limits must be positive" unless low.positive? && high.positive?
        raise ArgumentError, "log axis minimum must be less than maximum" if low == high && options[:min] && options[:max]

        high = low * 10 if low == high
        raise ArgumentError, "log axis minimum must be less than maximum" unless low < high

        @ticks = Ticks.log(low, high)
        @domain = [low, high]
      end

      def map(value)
        number = Data.number(value)
        return nil unless number&.positive?

        (@range[0] + ((Math.log10(number) - Math.log10(@domain[0])) * (@range[1] - @range[0]) / (Math.log10(@domain[1]) - Math.log10(@domain[0]))))
      end

      def format(value) = Ticks.number_label(value)

      private

      def axis_limit(value, fallback, name)
        return fallback if value.nil?

        number = Data.number(value)
        raise ArgumentError, "log axis #{name} must be finite and positive" unless number&.positive?

        number
      end
    end

    class Band
      attr_reader :domain, :ticks
      attr_accessor :range

      def initialize(values, options = {})
        values = values.compact.uniq
        order = options[:order]
        values = order.select { |value| values.include?(value) } + (values - order) if order
        @domain = @ticks = values
      end

      def map(value)
        index = @domain.index(value)
        return nil unless index

        @range[0] + ((index + 0.5) * (@range[1] - @range[0]) / @domain.length)
      end

      def bandwidth = (@range[1] - @range[0]) / [@domain.length, 1].max
      def format(value) = value.to_s
    end
  end

  module TextMetrics
    module_function

    def width(text, size = 12)
      if Inkplot.config.font
        font = font_for(size)
        return font.measure(text.to_s)[0]
      end

      text.to_s.each_char.sum { |character| character.ascii_only? ? size * 0.58 : size }
    rescue LoadError
      raise if Inkplot.config.font

      text.to_s.length * size * 0.58
    end

    def font_for(size = 12)
      require "glyphic"
      return Glyphic.load(Inkplot.config.font, size: size) if Inkplot.config.font

      Glyphic.default
    rescue LoadError => e
      raise LoadError, "font metrics need glyphic; install it with `gem install glyphic` (#{e.message})"
    end
  end

  module Theme
    PALETTE = %w[#0072B2 #E69F00 #009E73 #D55E00 #CC79A7 #56B4E9 #F0E442 #333333].freeze
    NAMED_COLORS = %w[red blue green black white orange gray grey purple yellow cyan magenta pink brown navy teal lime maroon olive silver aqua fuchsia rebeccapurple
                      transparent].freeze
    VALUES = {
      light: { background: "#FFFFFF", foreground: "#20242B", grid: "#E7EAF0", axis: "#626B78" },
      dark: { background: "#171B22", foreground: "#E8ECF2", grid: "#303744", axis: "#A9B2C0" }
    }.freeze

    module_function

    def colors(name)
      VALUES.fetch(name.to_sym) { raise ArgumentError, "theme must be :light or :dark" }
    end

    def series_color(index, theme)
      color = PALETTE[index % PALETTE.length]
      return color if index < PALETTE.length || theme.to_sym == :light

      rgb = color.delete_prefix("#").scan(/../).map { |part| part.to_i(16) }
      rgb.map { |channel| ((channel * 0.72) + (255 * 0.28)).round }.map { |channel| format("%02X", channel) }.join.prepend("#")
    end

    def validate_color(color)
      return nil if color.nil?

      value = color.to_s
      return value if value.match?(/\A(?:#[\da-fA-F]{3,4}|#[\da-fA-F]{6}|#[\da-fA-F]{8})\z/) || NAMED_COLORS.include?(value.downcase)

      raise ArgumentError, "color must be a CSS color name or hexadecimal value"
    end
  end

  class Builder
    attr_reader :width, :height, :theme, :series, :x_options, :y_options, :notes
    attr_accessor :title_text, :x_label_text, :y_label_text, :legend_options

    def initialize(width: 640, height: 360, theme: :light, title: nil, x_label: nil, y_label: nil, **_options)
      @width = Integer(width)
      @height = Integer(height)
      raise ArgumentError, "chart dimensions must be at least 120×100" if @width < 120 || @height < 100

      @theme = theme.to_sym
      Theme.colors(@theme)
      @title_text = title
      @x_label_text = x_label
      @y_label_text = y_label
      @x_options = {}
      @y_options = {}
      @legend_options = { position: :top_right }
      @series = []
      @notes = []
    end

    def title(value) = @title_text = value.to_s

    def x_axis(label: nil, type: nil, scale: nil, min: nil, max: nil, order: nil)
      @x_label_text = label.to_s if label
      @x_options = { type:, scale:, min:, max:, order: }.compact
    end

    def y_axis(label: nil, type: nil, scale: nil, min: nil, max: nil)
      @y_label_text = label.to_s if label
      @y_options = { type:, scale:, min:, max: }.compact
    end

    def legend(position: :top_right) = @legend_options = { position: position.to_sym }

    def line(x, y = nil, label: nil, color: nil, dash: false, gaps: :break, **)
      add(:line, Data.points(x, y), label:, color:, dash:, gaps:, **)
    end

    def scatter(x, y = nil, label: nil, color: nil, size: nil, **)
      add(:scatter, Data.points(x, y, size:), label:, color:, **)
    end

    def area(x, y = nil, label: nil, color: nil, **)
      add(:area, Data.points(x, y), label:, color:, **)
    end

    def step(x, y = nil, label: nil, color: nil, **)
      add(:step, Data.points(x, y), label:, color:, **)
    end

    def bar(categories, values = nil, label: nil, color: nil, horizontal: false, stacked: false, **)
      points = Data.points(categories, values)
      add(:bar, points, label:, color:, horizontal:, stacked:, **)
    end

    def hline(value, label: nil, color: nil, dash: true)
      number = Data.number(value)
      raise ArgumentError, "horizontal rule value must be finite and numeric" unless number

      @notes << { type: :hline, value: number, label:, color: Theme.validate_color(color), dash: }
    end

    def vline(value, label: nil, color: nil, dash: true)
      @notes << { type: :vline, value:, label:, color: Theme.validate_color(color), dash: }
    end

    def add(type, points, label: nil, color: nil, **options)
      raise ArgumentError, "unsupported chart mark: #{type}" unless %i[line scatter bar area step].include?(type.to_sym)
      raise ArgumentError, "gaps must be :break or :connect" if options[:gaps] && !%i[break connect].include?(options[:gaps])

      @series << Series.new(type: type.to_sym, points:, label: label&.to_s, color: Theme.validate_color(color), options:)
      self
    end
  end

  class Chart
    attr_reader :builder

    def initialize(builder)
      @builder = builder
    end

    def width = builder.width
    def height = builder.height

    def to_svg(width: self.width, height: self.height)
      Renderers::SVG.render(SceneBuilder.call(self, width: width, height: height))
    end

    def save(path, width: self.width, height: self.height)
      case File.extname(String(path)).downcase
      when ".svg" then File.write(path, to_svg(width:, height:))
      else raise ArgumentError, "output path must end in .svg"
      end
      path
    end

    private

    def series = builder.series
  end

  module SceneBuilder
    module_function

    def call(chart, width:, height:)
      builder = chart.builder
      width = Integer(width)
      height = Integer(height)
      raise ArgumentError, "chart dimensions must be at least 120×100" if width < 120 || height < 100

      series = builder.series
      raise ArgumentError, "chart has no data marks" if series.empty?

      warn "Inkplot cycles its eight-color palette after eight series." if series.length > Theme::PALETTE.length
      colors = Theme.colors(builder.theme)
      x_values = series.flat_map { |item| item.points.flat_map { |point| [point[:x], point[:x2]].compact } }
      y_values = series.flat_map { |item| item.points.map { |point| point[:y] } }
      if series.any? { |item| item.options[:stacked] }
        totals = stacked_totals(series)
        y_values.concat(totals)
      end
      horizontal = series.any? { |item| item.type == :bar && item.options[:horizontal] }
      if horizontal
        x_values = series.flat_map { |item| item.points.map { |point| point[:y] } }
        y_values = series.flat_map { |item| item.points.map { |point| point[:x] } }
        x_values.concat(stacked_totals(series)) if series.any? { |item| item.options[:stacked] }
      end
      x_options = builder.x_options
      y_options = builder.y_options
      x_scale = build_scale(x_values, x_options, :x, series)
      y_scale = build_scale(y_values, y_options, :y, series)
      x_ticks = ticks(x_scale)
      y_ticks = ticks(y_scale)
      left = (y_ticks.map { |tick| TextMetrics.width(y_scale.format(tick), 11) }.max.to_f.ceil + 14).clamp(42, 120)
      bottom = 34
      bottom += 20 if builder.x_label_text
      left += 18 if builder.y_label_text
      top = builder.title_text ? 40 : 18
      legend_items = series.each_with_index.filter_map { |item, index| [item.label, item.color || Theme.series_color(index, builder.theme)] if item.label }
      legend_items.uniq!(&:first)
      legend_width = [legend_items.map { |label, _| TextMetrics.width(label, 11) }.max.to_f.ceil + 30, 120].max
      right = builder.legend_options[:position].to_s.end_with?("right") && legend_items.length > 1 ? legend_width + 18 : 18
      x_scale.range = [left, width - right]
      y_scale.range = [height - bottom, top]
      clip = [left, top, width - right, height - bottom]
      marks = []
      elements = [{ type: :rect, x: 0, y: 0, width:, height:, fill: colors[:background] }]

      y_ticks.each do |tick|
        y = y_scale.map(tick)
        next unless y

        elements << { type: :line, class: "grid-line", points: [[left, y], [width - right, y]], stroke: colors[:grid], width: 1 }
        elements << { type: :text, x: left - 8, y: y + 4, text: y_scale.format(tick), fill: colors[:axis], anchor: :end, size: 11 }
      end
      x_ticks.each_with_index do |tick, _index|
        x = x_scale.map(tick)
        next unless x

        label = x_scale.format(tick)
        elements << { type: :line, class: "grid-line", points: [[x, top], [x, height - bottom]], stroke: colors[:grid], width: 1 } if x_scale.is_a?(Scales::Band)
        elements << { type: :text, x:, y: height - bottom + 18, text: label, fill: colors[:axis], anchor: :middle, size: 10 }
      end
      elements << { type: :line, class: "axis-line", points: [[left, top], [left, height - bottom], [width - right, height - bottom]], stroke: colors[:axis], width: 1 }
      elements << { type: :text, x: width / 2.0, y: 22, text: builder.title_text, fill: colors[:foreground], anchor: :middle, size: 15 } if builder.title_text
      if builder.x_label_text
        elements << { type: :text, x: (left + width - right) / 2.0, y: height - 5, text: builder.x_label_text, fill: colors[:foreground], anchor: :middle,
                      size: 11 }
      end
      elements << { type: :text, x: 14, y: height / 2.0, text: builder.y_label_text, fill: colors[:foreground], anchor: :middle, size: 11, rotate: -90 } if builder.y_label_text

      bars = series.select { |item| item.type == :bar }
      bar_index = 0
      positive_stack = Hash.new(0.0)
      negative_stack = Hash.new(0.0)
      series.each_with_index do |item, index|
        color = item.color || Theme.series_color(index, builder.theme)
        points = item.points
        if item.type == :bar
          current_bar_index = bar_index
          bar_index += 1
          total = [bars.length, 1].max
          points.each do |point|
            next unless point[:y] && point[:x]

            if item.options[:horizontal]
              band = y_scale.bandwidth * 0.72
              value = point[:y]
              base = if item.options[:stacked]
                       (value.negative? ? negative_stack : positive_stack)[point[:x]]
                     else
                       0
                     end
              finish = base + value
              if item.options[:stacked]
                (value.negative? ? negative_stack : positive_stack)[point[:x]] = finish
              end
              value = x_scale.map(finish)
              zero = x_scale.map(base)
              next unless value && zero

              category_y = y_scale.map(point[:x])
              offset = item.options[:stacked] ? 0 : (current_bar_index - ((total - 1) / 2.0)) * band
              marks << { type: :rect, class: "bar-mark", series_index: index, x: [value, zero].min, y: category_y - (band / 2) + offset, width: (value - zero).abs, height: band,
                         fill: color }
            else
              band = x_scale.bandwidth * (item.options[:stacked] ? 0.78 : 0.82 / total)
              x = x_scale.map(point[:x])
              value = point[:y]
              stack = value.negative? ? negative_stack : positive_stack
              base = item.options[:stacked] ? stack[point[:x]] : 0
              stack[point[:x]] = base + value if item.options[:stacked]
              y0 = y_scale.map(base)
              y1 = y_scale.map(base + value)
              offset = item.options[:stacked] ? 0 : (current_bar_index - ((total - 1) / 2.0)) * band
              marks << { type: :rect, class: "bar-mark", series_index: index, x: x - (band / 2) + offset, y: [y0, y1].min, width: [band - 1, 1].max, height: (y0 - y1).abs,
                         fill: color }
            end
          end
          next
        end
        drawable = points.map do |point|
          px = x_scale.map(point[:x])
          py = y_scale.map(point[:y])
          px && py && [px, py, point]
        end
        case item.type
        when :line, :step
          segments = drawable_segments(drawable, item.options[:gaps] == :connect)
          segments.each do |segment|
            coordinates = segment.each_with_index.flat_map do |(px, py, _point), point_index|
              if item.type == :step && point_index.positive?
                [[px, segment[point_index - 1][1]], [px, py]]
              else
                [[px, py]]
              end
            end
            marks << { type: :line, class: "mark-line", series_index: index, points: coordinates, stroke: color, width: item.options[:width] || 2, dash: item.options[:dash] }
          end
        when :area
          drawable_segments(drawable, false).each do |segment|
            next if segment.empty?

            zero = y_scale.map(y_scale.is_a?(Scales::Log) ? y_scale.domain.first : 0)
            polygon = [[segment.first[0], zero]] + segment.map { |px, py, _| [px, py] } + [[segment.last[0], zero]]
            marks << { type: :polygon, class: "mark-area", series_index: index, points: polygon, fill: color, opacity: 0.28 }
            marks << { type: :line, class: "series-area-line", series_index: index, points: segment.map { |px, py, _| [px, py] }, stroke: color, width: 2 }
          end
        when :scatter
          valid = drawable.compact
          range = valid.filter_map { |_, _, point| point[:size] }.minmax
          valid.each do |px, py, point|
            radius = 4
            radius += (point[:size] - range[0]) / (range[1] - range[0]) * 5 if point[:size] && range && range[1] > range[0]
            marks << { type: :circle, class: "series-point", series_index: index, cx: px, cy: py, r: radius, fill: color, stroke: colors[:background], stroke_width: 1 }
          end
        end
      end

      builder.notes.each do |note|
        color = note[:color] || colors[:axis]
        case note[:type]
        when :hline
          y = y_scale.map(note[:value])
          marks << { type: :line, class: "rule-line", points: [[left, y], [width - right, y]], stroke: color, width: 1.5, dash: note[:dash], label: note[:label] } if y
        when :vline
          x = x_scale.map(note[:value])
          marks << { type: :line, class: "rule-line", points: [[x, top], [x, height - bottom]], stroke: color, width: 1.5, dash: note[:dash] } if x
        end
      end

      if legend_items.length > 1 || (legend_items.length == 1 && builder.legend_options[:show_single])
        x, y = legend_position(builder.legend_options[:position], clip, legend_items.length, legend_width)
        legend_items.each_with_index do |(label, color), index|
          current_y = y + (index * 18)
          elements << { type: :line, points: [[x, current_y - 4], [x + 16, current_y - 4]], stroke: color, width: 2 }
          elements << { type: :text, x: x + 22, y: current_y, text: label, fill: colors[:foreground], anchor: :start, size: 11 }
        end
      end
      Scene.new(width:, height:, background: colors[:background], clip:, marks:, elements:)
    end

    def build_scale(values, options, axis, series)
      explicit = options[:scale] || options[:type]
      horizontal_bar = series.any? { |item| item.type == :bar && item.options[:horizontal] }
      bar_band = series.any? { |item| item.type == :bar && ((item.options[:horizontal] && axis == :y) || (!item.options[:horizontal] && axis == :x)) }
      if explicit == :band || (explicit.nil? && (bar_band || values.any? { |value| !Data.number(value) }))
        Scales::Band.new(values, options)
      elsif explicit == :log
        warn "Inkplot ignores zero and negative values on a log axis." if values.any? { |value| (number = Data.number(value)) && !number.positive? }
        Scales::Log.new(values, options)
      else
        raise ArgumentError, "unknown #{axis}-axis scale: #{explicit}" if explicit && explicit != :linear

        include_zero = series.any? do |item|
          (axis == :y && %i[bar area].include?(item.type) && !item.options[:horizontal]) ||
            (horizontal_bar && axis == :x && item.options[:horizontal])
        end
        Scales::Linear.new(values, options, include_zero: include_zero)
      end
    end

    def ticks(scale)
      scale.ticks
    end

    def stacked_totals(series)
      series.select { |item| item.type == :bar && item.options[:stacked] }
            .flat_map(&:points).group_by { |point| point[:x] }.values.flat_map do |points|
        [points.sum { |point| [Data.number(point[:y]) || 0, 0].max }, points.sum { |point| [Data.number(point[:y]) || 0, 0].min }]
      end
    end

    def drawable_segments(points, connect)
      values = connect ? points.compact : points
      values.each_with_object([[]]) do |point, segments|
        if point
          segments.last << point
        elsif !connect && !segments.last.empty?
          segments << []
        end
      end.reject(&:empty?)
    end

    def legend_position(position, clip, count, legend_width = 120)
      x0, y0, x1, y1 = clip
      case position.to_sym
      when :top_left then [x0 + 8, y0 + 18]
      when :bottom_left then [x0 + 8, y1 - (count * 18)]
      when :bottom_right then [x1 - legend_width + 8, y1 - (count * 18)]
      when :top then [((x0 + x1) / 2.0) - (legend_width / 2), y0 + 16]
      else [x1 - legend_width + 8, y0 + 18]
      end
    end
  end
end
