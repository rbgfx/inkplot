# frozen_string_literal: true

require "tempfile"
require "lookalike"

RSpec.describe "Inkplot PNG output" do
  let(:chart) do
    Inkplot.plot do |plot|
      plot.line([0, 1, 2], [0, 2, 1], color: "#1F4E79", cap: :round, join: :round)
      plot.line([0, 1, 2], [1, 0, 2], color: "#D55E00", join: :bevel)
      plot.scatter([0, 1, 2], [0, 2, 1], size: [1, 2, 3])
      plot.annotate(1, 1, "peak")
    end
  end

  it "gives an installation hint when optional raster dependencies are absent" do
    expect { chart.to_png(scale: 0) }.to raise_error(ArgumentError, /positive integer/)
    expect { chart.to_png }.to raise_error(LoadError, /install them with `gem install tessel glyphic`/) unless raster_dependencies?
  end

  it "renders anti-aliased PNG bytes, honors scale, and saves PNG files" do
    skip "tessel and glyphic are not on the load path" unless raster_dependencies?

    image = chart.to_image(scale: 2)
    decoded = Tessel.decode(chart.to_png)
    expect([image.width, image.height]).to eq([1280, 720])
    expect([decoded.width, decoded.height]).to eq([640, 360])
    expect(image.bytes.bytes.each_slice(4).any? { |red, green, blue, alpha| alpha == 255 && red.between?(1, 254) && green.between?(1, 254) && blue.between?(1, 254) }).to be(true)

    file = Tempfile.new(["inkplot", ".png"])
    chart.save(file.path, scale: 2)
    expect(Tessel.read(file.path).width).to eq(1280)
  ensure
    file&.unlink
  end

  it "preserves edge colors when downsampling transparent pixels" do
    skip "tessel is not on the load path" unless raster_dependencies?

    source = Tessel::Image.from_rgba(2, 2, ([255, 0, 0, 255] + ([0, 0, 0, 0] * 3)).pack("C*"))
    pixel = Inkplot::Renderers::PNG.send(:downsample, source).bytes.bytes

    expect(pixel).to eq([255, 0, 0, 64])
  end

  it "renders and decodes every gallery chart" do
    skip "tessel and glyphic are not on the load path" unless raster_dependencies?

    require_relative "../examples/gallery"
    InkplotGallery.charts.each do |pair|
      example = pair.last
      decoded = Tessel.decode(example.to_png)
      expect([decoded.width, decoded.height]).to eq([example.width, example.height])
    end
  end

  it "matches stable PNG snapshots for all gallery charts" do
    require_relative "../examples/gallery"

    previous_font = Inkplot.config.font
    Inkplot.config.font = nil # Use Glyphic's embedded bitmap font; never depend on system fonts.
    InkplotGallery.charts.each do |name, chart|
      image = Tessel.decode(chart.to_png(width: 320, height: 180))
      Lookalike.assert_snapshot(image, "inkplot/#{name}", mode: :channel)
    end
  ensure
    Inkplot.config.font = previous_font
  end

  it "uses the configured TrueType font when one is available" do
    previous_font = Inkplot.config.font
    skip "tessel and glyphic are not on the load path" unless raster_dependencies?

    font_path = ["/System/Library/Fonts/Supplemental/Arial.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"].find { |path| File.file?(path) }
    skip "no test TrueType font is installed" unless font_path

    Inkplot.config.font = font_path
    expect(Tessel.decode(chart.to_png).width).to eq(chart.width)
  ensure
    Inkplot.config.font = previous_font
  end

  it "warns when fallback bitmap text receives Unicode" do
    skip "tessel and glyphic are not on the load path" unless raster_dependencies?

    previous_font = Inkplot.config.font
    Inkplot.config.font = nil
    unicode_chart = Inkplot.plot(title: "日本語") { |plot| plot.line([0, 1], [1, 2]) }
    expect { unicode_chart.to_png }.to output(/ASCII-only/).to_stderr
  ensure
    Inkplot.config.font = previous_font
  end

  def raster_dependencies?
    require "tessel"
    require "glyphic"
    true
  rescue LoadError
    false
  end
end
