# frozen_string_literal: true

module Inkplot
  module Renderers
    module PNG
      # ponytail: 2x supersampling limits edge coverage accuracy; raise this or add exact area integration if visual tests show artifacts.
      ANTIALIAS = 2
      COLORS = {
        "red" => "#FF0000", "blue" => "#0000FF", "green" => "#008000", "black" => "#000000", "white" => "#FFFFFF",
        "orange" => "#FFA500", "gray" => "#808080", "grey" => "#808080", "purple" => "#800080", "yellow" => "#FFFF00",
        "cyan" => "#00FFFF", "magenta" => "#FF00FF", "pink" => "#FFC0CB", "brown" => "#A52A2A", "navy" => "#000080",
        "teal" => "#008080", "lime" => "#00FF00", "maroon" => "#800000", "olive" => "#808000", "silver" => "#C0C0C0",
        "aqua" => "#00FFFF", "fuchsia" => "#FF00FF", "rebeccapurple" => "#663399", "transparent" => "#00000000"
      }.freeze

      module_function

      def render(scene, scale: 1)
        scale = Float(scale)
        raise ArgumentError, "scale must be a positive integer" unless scale.positive? && scale.finite? && scale == scale.to_i

        require_dependencies
        scale = scale.to_i
        factor = scale * ANTIALIAS
        image = Tessel::Image.new(scene.width * factor, scene.height * factor)
        warn "Inkplot PNG fallback font is ASCII-only; set Inkplot.config.font for Unicode text." if !Inkplot.config.font && (scene.elements + scene.marks).any? { |element| element[:type] == :text && element[:text].to_s.match?(/[^\x00-\x7F]/) }
        fonts = {}
        scene.elements.each { |element| draw(image, element, factor, fonts:) }

        seen = {}
        clip = scene.clip.map { |coordinate| coordinate * factor }
        scene.marks.each do |mark|
          if mark[:type] == :circle
            key = [mark[:series_index], mark[:cx].floor, mark[:cy].floor]
            next if seen[key]

            seen[key] = true
          end
          draw(image, mark, factor, clip:, fonts:)
        end
        downsample(image)
      end

      def encode(image)
        require_dependencies
        Tessel::PNG.encode(image)
      end

      def require_dependencies
        require "tessel"
        require "glyphic"
      rescue LoadError => e
        raise LoadError, "PNG output requires tessel and glyphic; install them with `gem install tessel glyphic` (#{e.message})", cause: e
      end
      private_class_method :require_dependencies

      def color(value)
        text = value.to_s
        text = COLORS.fetch(text.downcase, text)
        hex = text.delete_prefix("#")
        hex = hex.chars.flat_map { |digit| [digit, digit] }.join if [3, 4].include?(hex.length)
        raise ArgumentError, "unsupported PNG color: #{value}" unless [6, 8].include?(hex.length) && hex.match?(/\A[\da-fA-F]+\z/)

        channels = hex.scan(/../).map { |part| part.to_i(16) }
        channels << 255 if channels.length == 3
        channels
      end
      private_class_method :color

      def draw(image, element, factor, fonts:, clip: nil)
        case element[:type]
        when :rect
          rect(image, element, factor, clip)
        when :line
          Raster::Stroker.draw(image, element, factor, clip)
        when :polygon
          Raster::PathFiller.fill(image, element[:points].map { |point| point.map { |value| value * factor } }, color(element[:fill]),
                                  clip: scaled_clip(clip), opacity: element[:opacity] || 1)
        when :circle
          circle(image, element, factor, clip)
        when :text
          text(image, element, factor, clip, fonts)
        end
      end
      private_class_method :draw

      def rect(image, element, factor, clip)
        x = (element[:x] * factor).round
        y = (element[:y] * factor).round
        width = (element[:width] * factor).round
        height = (element[:height] * factor).round
        if clip
          left, top, right, bottom = clip.map(&:round)
          x0 = [x, left].max
          y0 = [y, top].max
          x1 = [x + width, right].min
          y1 = [y + height, bottom].min
          return if x0 >= x1 || y0 >= y1

          x = x0
          y = y0
          width = x1 - x0
          height = y1 - y0
        end
        image.fill_rect(x, y, width, height, color(element[:fill]), blend: :alpha)
      end
      private_class_method :rect

      def circle(image, element, factor, clip)
        cx = element[:cx] * factor
        cy = element[:cy] * factor
        radius = element[:r] * factor
        pixels = color(element[:fill])
        border = color(element[:stroke]) if element[:stroke] && element[:stroke_width].to_f.positive?
        if border
          stroke_radius = element[:stroke_width] * factor / 2
          circle_pixels(image, cx, cy, radius + stroke_radius, border, clip)
          circle_pixels(image, cx, cy, [radius - stroke_radius, 0].max, pixels, clip)
        else
          circle_pixels(image, cx, cy, radius, pixels, clip)
        end
      end
      private_class_method :circle

      def circle_pixels(image, cx, cy, radius, pixels, clip)
        top = [0, (cy - radius).floor].max
        bottom = [image.height - 1, (cy + radius).ceil].min
        if clip
          top = [top, clip[1].floor].max
          bottom = [bottom, clip[3].ceil - 1].min
        end
        (top..bottom).each do |y|
          dy = y + 0.5 - cy
          half_width = Math.sqrt([(radius * radius) - (dy * dy), 0].max)
          left = [0, (cx - half_width).ceil].max
          right = [image.width - 1, (cx + half_width).floor].min
          if clip
            left = [left, clip[0].floor].max
            right = [right, clip[2].ceil - 1].min
          end
          image.fill_rect(left, y, right - left + 1, 1, pixels, blend: :alpha) if left <= right
        end
      end
      private_class_method :circle_pixels

      def text(image, element, factor, clip, fonts)
        string = element[:text].to_s
        return if string.empty?

        mask, ascent = text_mask(string, element[:size] || 12, factor, color(element[:fill]), fonts)
        anchor = { start: 0, middle: mask.width / 2.0, end: mask.width }.fetch(element[:anchor] || :start)
        pivot_x = element[:x] * factor
        pivot_y = element[:y] * factor
        angle = (element[:rotate] || 0) * Math::PI / 180
        cosine = Math.cos(angle)
        sine = Math.sin(angle)
        bytes = mask.bytes
        mask.height.times do |row|
          mask.width.times do |column|
            offset = ((row * mask.width) + column) * 4
            alpha = bytes.getbyte(offset + 3)
            next if alpha.zero?

            local_x = column + 0.5 - anchor
            local_y = row + 0.5 - ascent
            x = (pivot_x + (local_x * cosine) - (local_y * sine)).round
            y = (pivot_y + (local_x * sine) + (local_y * cosine)).round
            next if clip && !(x >= clip[0] && x < clip[2] && y >= clip[1] && y < clip[3])

            image.fill_rect(x, y, 1, 1, bytes.byteslice(offset, 4).bytes, blend: :alpha)
          end
        end
      end
      private_class_method :text

      def text_mask(string, size, factor, pixels, fonts)
        if Inkplot.config.font
          font_size = [1, (size * factor).round].max
          font = fonts[[Inkplot.config.font, font_size]] ||= Glyphic.load(Inkplot.config.font, size: font_size)
          width, height = font.measure(string)
          mask = Tessel::Image.new([1, width].max, [1, height].max)
          font.draw(mask, 0, 0, string, color: pixels)
          [mask, font.ascent]
        else
          font = fonts[:default] ||= Glyphic.default
          mask = font.render(string, color: pixels)
          ratio = size * factor / font.line_height
          width = [1, (mask.width * ratio).round].max
          height = [1, (mask.height * ratio).round].max
          mask = mask.scale_nearest(width, height)
          [mask, (font.ascent * ratio).round]
        end
      end
      private_class_method :text_mask

      def scaled_clip(clip)
        clip&.map(&:round)
      end
      private_class_method :scaled_clip

      def downsample(image)
        factor = ANTIALIAS
        width = image.width / factor
        height = image.height / factor
        source = image.bytes
        output = String.new(capacity: width * height * 4, encoding: Encoding::BINARY)
        height.times do |y|
          width.times do |x|
            channels = [0, 0, 0]
            alpha = 0
            factor.times do |dy|
              factor.times do |dx|
                offset = ((((y * factor) + dy) * image.width) + ((x * factor) + dx)) * 4
                sample_alpha = source.getbyte(offset + 3)
                alpha += sample_alpha
                3.times { |channel| channels[channel] += source.getbyte(offset + channel) * sample_alpha }
              end
            end
            channels.map! { |value| alpha.zero? ? 0 : (value.to_f / alpha).round }
            channels << (alpha.to_f / (factor * factor)).round
            output << channels.pack("C4")
          end
        end
        Tessel::Image.from_rgba(width, height, output)
      end
      private_class_method :downsample
    end

    module Raster
      module PathFiller
        module_function

        def fill(image, points, color, clip: nil, opacity: 1)
          return if points.length < 3

          min_y = [points.map(&:last).min.floor, 0].max
          max_y = [points.map(&:last).max.ceil, image.height].min
          clip_top, clip_bottom = clip ? [clip[1], clip[3]] : [0, image.height]
          min_y = [min_y, clip_top].max
          max_y = [max_y, clip_bottom].min
          rgba = color.dup
          rgba[3] = (rgba[3] * opacity).round
          (min_y...max_y).each do |y|
            scan_y = y + 0.5
            crossings = points.each_with_index.filter_map do |(x0, y0), index|
              x1, y1 = points[(index + 1) % points.length]
              next if y0 == y1 || !((y0 <= scan_y && scan_y < y1) || (y1 <= scan_y && scan_y < y0))

              [x0 + ((scan_y - y0) * (x1 - x0) / (y1 - y0)), y1 > y0 ? 1 : -1]
            end.sort_by(&:first)
            winding = 0
            start = nil
            crossings.each do |x, direction|
              previous = winding
              winding += direction
              start = x if previous.zero? && !winding.zero?
              next unless !previous.zero? && winding.zero? && start

              left = [0, (start - 0.5).ceil].max
              right = [image.width, (x - 0.5).ceil].min
              if clip
                left = [left, (clip[0] - 0.5).ceil].max
                right = [right, (clip[2] - 0.5).ceil].min
              end
              image.fill_rect(left, y, right - left, 1, rgba, blend: :alpha) if left < right
              start = nil
            end
          end
        end
      end

      module Stroker
        module_function

        def draw(image, element, factor, clip)
          points = element[:points].map { |x, y| [x * factor, y * factor] }
          return if points.length < 2

          width = (element[:width] || 1) * factor
          color = PNG.send(:color, element[:stroke])
          segments = element[:dash] ? dashed(points, 5 * factor, 4 * factor) : points.each_cons(2).to_a
          segments.each do |first, last|
            polygon = segment_polygon(first, last, width)
            PathFiller.fill(image, polygon, color, clip: PNG.send(:scaled_clip, clip))
          end
          return if element[:dash]

          cap = (element[:cap] || :butt).to_sym
          join = (element[:join] || :miter).to_sym
          [points.first, points.last].each { |x, y| PNG.send(:circle_pixels, image, x, y, width / 2, color, clip) } if cap == :round
          case join
          when :round
            points[1...-1].each { |x, y| PNG.send(:circle_pixels, image, x, y, width / 2, color, clip) }
          when :miter
            points.each_cons(3) { |previous, current, following| miter_join(image, previous, current, following, width, color, clip) }
          when :bevel
            points.each_cons(3) { |previous, current, following| bevel_join(image, previous, current, following, width, color, clip) }
          end
        end

        def segment_polygon(first, last, width)
          dx = last[0] - first[0]
          dy = last[1] - first[1]
          length = Math.sqrt((dx * dx) + (dy * dy))
          return [] if length.zero?

          nx = -dy * width / (2 * length)
          ny = dx * width / (2 * length)
          [[first[0] + nx, first[1] + ny], [last[0] + nx, last[1] + ny], [last[0] - nx, last[1] - ny], [first[0] - nx, first[1] - ny]]
        end
        private_class_method :segment_polygon

        def miter_join(image, previous, current, following, width, color, clip)
          first = unit(previous, current)
          second = unit(current, following)
          return unless first && second

          cross = (first[0] * second[1]) - (first[1] * second[0])
          return if cross.abs < 1e-9

          half = width / 2
          first_normal = [-first[1], first[0]]
          second_normal = [-second[1], second[0]]
          [-1, 1].each do |side|
            a = [current[0] + (first_normal[0] * half * side), current[1] + (first_normal[1] * half * side)]
            b = [current[0] + (second_normal[0] * half * side), current[1] + (second_normal[1] * half * side)]
            t = (((b[0] - a[0]) * second[1]) - ((b[1] - a[1]) * second[0])) / cross
            corner = [a[0] + (first[0] * t), a[1] + (first[1] * t)]
            corner = current if Math.hypot(corner[0] - current[0], corner[1] - current[1]) > width * 4
            PathFiller.fill(image, [a, corner, b], color, clip: PNG.send(:scaled_clip, clip))
          end
        end
        private_class_method :miter_join

        def unit(first, last)
          dx = last[0] - first[0]
          dy = last[1] - first[1]
          length = Math.hypot(dx, dy)
          length.zero? ? nil : [dx / length, dy / length]
        end
        private_class_method :unit

        def bevel_join(image, previous, current, following, width, color, clip)
          first = unit(previous, current)
          second = unit(current, following)
          return unless first && second

          first_normal = [-first[1], first[0]]
          second_normal = [-second[1], second[0]]
          [-1, 1].each do |side|
            a = [current[0] + (first_normal[0] * width * side / 2), current[1] + (first_normal[1] * width * side / 2)]
            b = [current[0] + (second_normal[0] * width * side / 2), current[1] + (second_normal[1] * width * side / 2)]
            PathFiller.fill(image, [current, a, b], color, clip: PNG.send(:scaled_clip, clip))
          end
        end
        private_class_method :bevel_join

        def dashed(points, dash, gap)
          result = []
          on = true
          remaining = dash
          points.each_cons(2) do |first, last|
            dx = last[0] - first[0]
            dy = last[1] - first[1]
            length = Math.sqrt((dx * dx) + (dy * dy))
            next if length.zero?

            position = 0.0
            while position < length
              step = [remaining, length - position].min
              if on && step.positive?
                start = [first[0] + (dx * position / length), first[1] + (dy * position / length)]
                finish = [first[0] + (dx * (position + step) / length), first[1] + (dy * (position + step) / length)]
                result << [start, finish]
              end
              position += step
              remaining -= step
              if remaining <= 1e-9
                on = !on
                remaining = on ? dash : gap
              end
            end
          end
          result
        end
        private_class_method :dashed
      end
    end
  end
end
