require 'test/unit'
require 'gdk_pixbuf2'
require 'redeye'

class TestRedeye < Test::Unit::TestCase
  def test_detect
    pixbuf = Gdk::Pixbuf.new(File.join(File.dirname(__FILE__)+"/drawing.png"))
    redeye = RedEye.new(pixbuf, 0, 0, pixbuf.width, pixbuf.height)
    n = 2
    blobs = redeye.identify_blobs(1.92).reject { |i|
      i.noPixels <= 4 or ! i.squareish?
    }.sort_by { |i| i.noPixels }
    biggest = blobs.size > n ?  blobs[-1 * n..-1] : blobs

    assert_equal 2, blobs.size
  end

  def test_highlight
    pixbuf = Gdk::Pixbuf.new(File.join(File.dirname(__FILE__)+"/drawing.png"))
    redeye = RedEye.new(pixbuf, 0, 0, pixbuf.width, pixbuf.height)
    n = 2
    blobs = redeye.identify_blobs(1.92).reject { |i|
      i.noPixels <= 4 or ! i.squareish?
    }.sort_by { |i| i.noPixels }
    biggest = blobs.size > n ?  blobs[-1 * n..-1] : blobs

    assert_equal 2, blobs.size

    blobs.each { |blob| redeye.highlight_blob(blob.id) }

    pixbuf.save(File.join(File.dirname(__FILE__)+"/highlight.jpg"), 'jpeg')

    offset = (127 * pixbuf.rowstride) + (44 * pixbuf.n_channels)
    pixel = pixbuf.pixels[offset,4]
    
    # Bright green
    assert_equal raw("\0\xff\0\xff"), pixel
  end

  def test_correct
    pixbuf = Gdk::Pixbuf.new(File.join(File.dirname(__FILE__)+"/drawing.png"))
    redeye = RedEye.new(pixbuf, 0, 0, pixbuf.width, pixbuf.height)
    n = 2
    blobs = redeye.identify_blobs(1.92).reject { |i|
      i.noPixels <= 4 or ! i.squareish?
    }.sort_by { |i| i.noPixels }
    biggest = blobs.size > n ?  blobs[-1 * n..-1] : blobs

    assert_equal 2, blobs.size

    blobs.each { |blob| redeye.correct_blob(blob.id) }

    pixbuf.save(File.join(File.dirname(__FILE__)+"/correct.jpg"), 'jpeg')


    offset = (127 * pixbuf.rowstride) + (44 * pixbuf.n_channels)
    pixel = pixbuf.pixels[offset,4]

    # Grey
    assert_equal raw("???\xff"), pixel
  end

  def raw(str)
    if RUBY_VERSION >= "1.9"
      str.force_encoding("ASCII-8BIT")
    else
      str
    end
  end
end
