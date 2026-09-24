# frozen_string_literal: true

module Inkplot
  module Renderers
    module Raster
      module_function

      def render(scene, scale: 1)
        scale = Integer(scale)
        raise ArgumentError, "scale must be a positive integer" unless scale.positive?

        begin
          require "tessel"
        rescue LoadError => e
          raise LoadError, "PNG output needs tessel; install it with `gem install tessel` (#{e.message})"
        end
        begin
          require "glyphic"
        rescue LoadError => e
          raise LoadError, "PNG output needs glyphic; install it with `gem install glyphic` (#{e.message})"
        end

        factor = scale * 2 # ponytail: 2× coverage sampling; raise this if raster diffs show visible edge artifacts.
        width = scene.width * scale
        height = scene.height * scale
        canvas = Tessel::Image.new(width * 2, height * 2, fill: color(scene.background))
        scene.elements.each { |element| draw_shape(canvas, element, factor) }
        clip = scene.clip.map { |value| value * factor }
        seen = {}
        scene.marks.each do |mark|
          if mark[:type] == :circle
            key = [mark[:series_index], (mark[:cx] * scale).round, (mark[:cy] * scale).round]
            next if seen[key]

            seen[key] = true
          end
          draw_shape(canvas, mark, factor, clip: clip)
        end
        image = downsample(canvas, width, height)
        draw_labels(image, scene.elements + scene.marks.select { |mark| mark[:type] == :text }, scale)
        image
      end

      def draw_shape(image, shape, factor, clip: nil)
        case shape[:type]
        when :rect
          rectangle(image, shape, factor, clip)
        when :line
          Stroker.stroke(image, shape[:points], color(shape[:stroke]), factor, (shape[:width] || 1) * factor, dash: shape[:dash], clip: clip)
        when :polygon
          rgba = color(shape[:fill])
          rgba[3] = (rgba[3] * (shape[:opacity] || 1)).round
          PathFiller.fill(image, shape[:points].map { |x, y| [x * factor, y * factor] }, rgba, clip: clip)
        when :circle
          cx, cy, radius = shape.values_at(:cx, :cy, :r).map { |value| value * factor }
          Circle.fill(image, cx, cy, radius, color(shape[:fill]), clip: clip)
          Circle.stroke(image, cx, cy, radius, color(shape[:stroke]), [shape[:stroke_width].to_f * factor, 1].max, clip: clip) if shape[:stroke]
        end
      end
      private_class_method :draw_shape

      def rectangle(image, shape, factor, clip)
        x, y, width, height = shape.values_at(:x, :y, :width, :height).map { |value| (value * factor).round }
        x0 = x
        y0 = y
        x1 = x + width
        y1 = y + height
        if clip
          x0 = [x0, clip[0].floor].max
          y0 = [y0, clip[1].floor].max
          x1 = [x1, clip[2].ceil].min
          y1 = [y1, clip[3].ceil].min
        end
        image.fill_rect(x0, y0, [x1 - x0, 0].max, [y1 - y0, 0].max, color(shape[:fill]), blend: :alpha)
      end
      private_class_method :rectangle

      def color(value)
        named = {
          "red" => [220, 40, 40], "blue" => [30, 90, 210], "green" => [0, 140, 80], "black" => [0, 0, 0], "white" => [255, 255, 255],
          "orange" => [230, 145, 0], "gray" => [128, 128, 128], "grey" => [128, 128, 128], "purple" => [128, 0, 128], "yellow" => [255, 255, 0],
          "cyan" => [0, 255, 255], "aqua" => [0, 255, 255], "magenta" => [255, 0, 255], "fuchsia" => [255, 0, 255], "pink" => [255, 192, 203],
          "brown" => [165, 42, 42], "navy" => [0, 0, 128], "teal" => [0, 128, 128], "lime" => [0, 255, 0], "maroon" => [128, 0, 0],
          "olive" => [128, 128, 0], "silver" => [192, 192, 192], "rebeccapurple" => [102, 51, 153], "transparent" => [0, 0, 0, 0]
        }
        return named.fetch(value.to_s.downcase) { [32, 36, 43] }.then { |channels| channels.length == 3 ? channels + [255] : channels } unless value.to_s.start_with?("#")

        hex = value.delete_prefix("#")
        hex = hex.chars.map { |digit| digit * 2 }.join if [3, 4].include?(hex.length)
        channels = hex.scan(/../).map { |channel| channel.to_i(16) }
        channels << 255 if channels.length == 3
        channels
      end
      private_class_method :color

      def downsample(source, width, height)
        input = source.bytes
        output = String.new(capacity: width * height * 4, encoding: Encoding::BINARY)
        height.times do |y|
          width.times do |x|
            4.times do |channel|
              total = 0
              2.times do |dy|
                2.times do |dx|
                  total += input.getbyte((((((y * 2) + dy) * source.width) + (x * 2) + dx) * 4) + channel)
                end
              end
              output << (total / 4).round
            end
          end
        end
        Tessel::Image.from_rgba(width, height, output)
      end
      private_class_method :downsample

      def draw_labels(image, elements, scale)
        font = TextMetrics.font_for(12 * scale)
        bitmap = Inkplot.config.font.nil?
        warned = false
        elements.each do |element|
          next unless element[:type] == :text

          text = element[:text].to_s
          if bitmap && !text.ascii_only? && !warned
            warn "Inkplot's built-in bitmap font is ASCII-only; set Inkplot.config.font to a TrueType font for Unicode labels."
            warned = true
          end
          label = text.encode("ASCII", invalid: :replace, undef: :replace, replace: "?") if bitmap
          label ||= text
          draw_text(image, font, label, element, scale)
        end
      end
      private_class_method :draw_labels

      def draw_text(image, font, text, element, scale)
        fill = color(element[:fill])
        anchor_x = (element[:x] * scale).round
        baseline_y = (element[:y] * scale).round
        glyph = font.render(text, color: fill)
        bitmap = Inkplot.config.font.nil?
        glyph = glyph.scale_nearest(glyph.width * scale, glyph.height * scale) if bitmap && scale > 1
        ascent = font.ascent * (bitmap ? scale : 1)
        pivot_x = case element[:anchor]
                  when :middle then glyph.width / 2.0
                  when :end then glyph.width.to_f
                  else 0.0
                  end
        if element[:rotate]
          pivot_y = ascent.to_f
          radians = element[:rotate] * Math::PI / 180
          source = glyph.bytes
          glyph.height.times do |gy|
            glyph.width.times do |gx|
              offset = ((gy * glyph.width) + gx) * 4
              alpha = source.getbyte(offset + 3)
              next if alpha.zero?

              dx = gx - pivot_x
              dy = gy - pivot_y
              px = (anchor_x + (dx * Math.cos(radians)) - (dy * Math.sin(radians))).round
              py = (baseline_y + (dx * Math.sin(radians)) + (dy * Math.cos(radians))).round
              blend_pixel(image, px, py, [fill[0], fill[1], fill[2], alpha])
            end
          end
        else
          image.blit(glyph, anchor_x - pivot_x.round, baseline_y - ascent, blend: :alpha)
        end
      end
      private_class_method :draw_text

      def blend_pixel(image, x, y, rgba)
        return unless x.between?(0, image.width - 1) && y.between?(0, image.height - 1)

        image.fill_rect(x, y, 1, 1, rgba, blend: :alpha)
      end
      private_class_method :blend_pixel

      module PathFiller
        module_function

        def fill(image, points, rgba, clip: nil)
          return if points.length < 3

          low = [points.map { |point| point[1] }.min.floor, clip ? clip[1].floor : 0, 0].max
          high = [points.map { |point| point[1] }.max.ceil, clip ? clip[3].ceil : image.height, image.height].min
          (low...high).each do |y|
            scan = y + 0.5
            crossings = points.each_with_index.filter_map do |point, index|
              next_point = points[(index + 1) % points.length]
              x1, y1 = point
              x2, y2 = next_point
              next if (y1 <= scan && y2 <= scan) || (y1 > scan && y2 > scan)

              [(x1 + ((scan - y1) * (x2 - x1) / (y2 - y1))), y2 > y1 ? 1 : -1]
            end.sort_by(&:first)
            winding = 0
            previous_x = nil
            crossings.each do |crossing_x, direction|
              fill_span(image, previous_x, crossing_x, y, rgba, clip) if winding != 0 && previous_x
              winding += direction
              previous_x = crossing_x
            end
          end
        end

        def fill_span(image, x1, x2, y, rgba, clip)
          left, right = [x1, x2].minmax
          left = [left.ceil, clip ? clip[0].ceil : 0].max
          right = [right.floor, clip ? clip[2].floor : image.width].min
          (left...right).each { |x| image[x, y] = rgba if rgba[3] == 255 }
          return if rgba[3] == 255

          (left...right).each { |x| image.fill_rect(x, y, 1, 1, rgba, blend: :alpha) }
        end
        private_class_method :fill_span
      end

      module Stroker
        module_function

        def stroke(image, points, rgba, factor, width, dash: false, clip: nil)
          return if points.length < 2

          return stroke_dashed(image, points, rgba, factor, width, clip) if dash

          scaled_points = points.map { |x, y| [(x * factor).round, (y * factor).round] }
          scaled_points.each_cons(2) do |(x0, y0), (x1, y1)|
            dx = x1 - x0
            dy = y1 - y0
            length = Math.hypot(dx, dy)
            next if length.zero?

            offset_x = -dy * width / (2 * length)
            offset_y = dx * width / (2 * length)
            polygon = [[x0 + offset_x, y0 + offset_y], [x1 + offset_x, y1 + offset_y], [x1 - offset_x, y1 - offset_y], [x0 - offset_x, y0 - offset_y]]
            PathFiller.fill(image, polygon, rgba, clip: clip)
          end
          scaled_points.each { |x, y| Circle.fill(image, x, y, width / 2.0, rgba, clip: clip) }
        end

        def stroke_dashed(image, points, rgba, factor, width, clip)
          dash_length = [width.round * 3, 6].max
          distance = 0
          points.each_cons(2) do |start_point, end_point|
            x0, y0 = start_point.map { |value| (value * factor).round }
            x1, y1 = end_point.map { |value| (value * factor).round }
            dx = (x1 - x0).abs
            dy = -(y1 - y0).abs
            sx = x0 < x1 ? 1 : -1
            sy = y0 < y1 ? 1 : -1
            error = dx + dy
            loop do
              draw_brush(image, x0, y0, width, rgba, clip) unless (distance / dash_length).odd?
              break if x0 == x1 && y0 == y1

              twice = 2 * error
              if twice >= dy
                error += dy
                x0 += sx
              end
              if twice <= dx
                error += dx
                y0 += sy
              end
              distance += 1
            end
          end
        end

        def draw_brush(image, x, y, width, rgba, clip)
          radius = [width / 2.0, 0.5].max
          (y - radius).floor.upto((y + radius).ceil) do |py|
            (x - radius).floor.upto((x + radius).ceil) do |px|
              next if ((px - x)**2) + ((py - y)**2) > radius**2
              next unless px.between?(0, image.width - 1) && py.between?(0, image.height - 1)
              next if clip && (px < clip[0] || px > clip[2] || py < clip[1] || py > clip[3])

              image.fill_rect(px, py, 1, 1, rgba, blend: :alpha)
            end
          end
        end
        private_class_method :draw_brush
      end

      module Circle
        module_function

        def fill(image, cx, cy, radius, rgba, clip: nil)
          low_y = [(cy - radius).floor, clip ? clip[1].floor : 0, 0].max
          high_y = [(cy + radius).ceil, clip ? clip[3].ceil : image.height - 1, image.height - 1].min
          (low_y..high_y).each do |y|
            span = Math.sqrt([(radius**2) - ((y - cy)**2), 0].max)
            left = [(cx - span).floor, clip ? clip[0].floor : 0, 0].max
            right = [(cx + span).ceil, clip ? clip[2].ceil : image.width - 1, image.width - 1].min
            image.fill_rect(left, y, right - left + 1, 1, rgba, blend: :alpha) if left <= right
          end
        end

        def stroke(image, cx, cy, radius, rgba, width, clip: nil)
          outer = radius + (width / 2.0)
          inner = [radius - (width / 2.0), 0].max
          low_y = [(cy - outer).floor, clip ? clip[1].floor : 0, 0].max
          high_y = [(cy + outer).ceil, clip ? clip[3].ceil : image.height - 1, image.height - 1].min
          (low_y..high_y).each do |y|
            dy = y - cy
            outer_span = Math.sqrt([(outer**2) - (dy**2), 0].max)
            outer_left = [(cx - outer_span).floor, clip ? clip[0].floor : 0, 0].max
            outer_right = [(cx + outer_span).ceil, clip ? clip[2].ceil : image.width - 1, image.width - 1].min
            inner_span = inner.zero? || dy.abs >= inner ? 0 : Math.sqrt((inner**2) - (dy**2))
            inner_left = (cx - inner_span).ceil
            inner_right = (cx + inner_span).floor
            left_width = [inner_left - outer_left, outer_right - outer_left + 1].min
            image.fill_rect(outer_left, y, left_width, 1, rgba, blend: :alpha) if left_width.positive?
            right_start = [inner_right + 1, outer_left].max
            right_width = outer_right - right_start + 1
            image.fill_rect(right_start, y, right_width, 1, rgba, blend: :alpha) if right_width.positive?
          end
        end
      end
    end
  end
end
