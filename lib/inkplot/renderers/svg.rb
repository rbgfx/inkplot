# frozen_string_literal: true

require "cgi"

module Inkplot
  module Renderers
    module SVG
      module_function

      def render(scene)
        width = scene.width
        height = scene.height
        x, y, right, bottom = scene.clip
        output = [%(<?xml version="1.0" encoding="UTF-8"?>),
                  %(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 #{width} #{height}" width="#{width}" height="#{height}" role="img" class="inkplot">),
                  %(<defs><clipPath id="plot-clip"><rect x="#{n(x)}" y="#{n(y)}" width="#{n(right - x)}" height="#{n(bottom - y)}"/></clipPath></defs>)]
        output.concat(scene.elements.map { |element| element_svg(element) }.compact)
        output << %(<g class="series-marks" clip-path="url(#plot-clip)">)
        current_series = nil
        scene.marks.each do |mark|
          content = element_svg(mark)
          next unless content

          if mark[:series_index] != current_series
            output << "</g>" if current_series
            current_series = mark[:series_index]
            output << %(<g class="series series-#{current_series}" data-series="#{current_series}">) if current_series
          end
          output << content
        end
        output << "</g>" if current_series
        output << "</g>"
        output << "</svg>"
        output.join
      end

      def element_svg(element)
        case element[:type]
        when :rect
          klass = element[:class] ? %( class="#{attr(element[:class])}") : ""
          %(<rect#{klass} x="#{n(element[:x])}" y="#{n(element[:y])}" width="#{n(element[:width])}" height="#{n(element[:height])}" fill="#{attr(element[:fill])}"/>)
        when :line
          points = element[:points]
          return if points.length < 2

          d = "M #{n(points[0][0])} #{n(points[0][1])} " + points.drop(1).map { |px, py| "L #{n(px)} #{n(py)}" }.join(" ")
          dash = element[:dash] ? %( stroke-dasharray="5 4") : ""
          %(<path class="#{attr(element[:class] || 'mark-line')}" d="#{d}" fill="none" stroke="#{attr(element[:stroke])}" stroke-width="#{n(element[:width] || 1)}"#{dash}/>)
        when :polygon
          points = element[:points]
          commands = points.drop(1).map { |px, py| "L #{n(px)} #{n(py)}" }.join(" ")
          d = "M #{n(points[0][0])} #{n(points[0][1])} #{commands} Z"
          %(<path class="#{attr(element[:class] || 'mark-area')}" d="#{d}" fill="#{attr(element[:fill])}" fill-opacity="#{n(element[:opacity] || 1)}"/>)
        when :circle
          %(<circle class="#{attr(element[:class] || 'mark-point')}" cx="#{n(element[:cx])}" cy="#{n(element[:cy])}" r="#{n(element[:r])}" fill="#{attr(element[:fill])}" stroke="#{attr(element[:stroke])}" stroke-width="#{n(element[:stroke_width] || 0)}"/>)
        when :text
          text = CGI.escapeHTML(element[:text].to_s)
          rotate = element[:rotate] ? %( transform="rotate(#{n(element[:rotate])} #{n(element[:x])} #{n(element[:y])})") : ""
          anchor = { start: "start", middle: "middle", end: "end" }.fetch(element[:anchor] || :start)
          %(<text x="#{n(element[:x])}" y="#{n(element[:y])}" fill="#{attr(element[:fill])}" text-anchor="#{anchor}" font-size="#{n(element[:size] || 12)}" font-family="system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif, 'Noto Sans CJK JP'"#{rotate}>#{text}</text>)
        end
      end

      def attr(value)
        CGI.escapeHTML(value.to_s)
      end

      def n(value)
        number = Float(value || 0)
        formatted = format("%.2f", number).sub(/0+\z/, "").sub(/\.\z/, "")
        formatted == "-0" ? "0" : formatted
      end
    end
  end
end
