require 'rmagick'
require 'opencv'

class ProcessedImage

  DETECTOR = OpenCV::CvHaarClassifierCascade::load("#{Rails.root}/lib/assets/haarcascade_frontalface_alt.xml")

  WIDTH_RATIO = 16.to_f
  HEIGHT_RATIO = 9.to_f
  TARGET_WIDTH = 542.to_f

  TARGET_RATIO = HEIGHT_RATIO / WIDTH_RATIO
  TARGET_HEIGHT = (TARGET_RATIO * TARGET_WIDTH).floor

  attr_reader :url

  def initialize(file, entry_id)
    @file = file
    @url = nil
    @entry_id = entry_id
  end

  def ping
    @ping ||= Magick::Image.ping(@file.path).first
  end

  def width
    @width ||= ping.columns.to_f
  end

  def height
    @height ||= ping.rows.to_f
  end

  def ratio
    @ratio ||= height / width
  end

  def landscape?
    ratio <= 1
  end

  def panoramic?
    ratio < TARGET_RATIO
  end

  def valid?
    width >= TARGET_WIDTH && height >= TARGET_HEIGHT && landscape?
  end

  def process
    success = false
    image = Magick::Image.read(@file.path).first
    image_file = Tempfile.new(["entry-#{@entry_id}-", ".jpg"])
    image_file.close
    if valid?
      resized_file = resize_to_fit(image)
      crop = find_best_crop(image, resized_file.path)
      image.crop!(crop[:x], crop[:y], crop[:width], crop[:height])
      image.write(image_file.path)
      @url = upload(image_file)
      success = true
    end
    success
  ensure
    image && image.destroy!
    resized_file && resized_file.close(true)
    image_file && image_file.close(true)
  end

  def upload(file)
    file.open
    uploader = EntryImageUploader.new
    uploader.store!(file)
    uploader.url
  end

  def resize_to_fit(image)
    file = Tempfile.new(["entry-#{@entry_id}-", ".png"])
    file.close

    geometry = Magick::Geometry.new(TARGET_WIDTH, TARGET_HEIGHT, 0, 0, Magick::MinimumGeometry)
    image.change_geometry!(geometry) do |width, height|
      image.resize!(width, height)
    end

    image.write(file.path)
    file
  end

  def find_best_crop(image, file_path)

    if panoramic?
      center = image.columns / 2
      center = find_center_of_objects(center, file_path, :x)
      crop_dimension = TARGET_WIDTH
      contrained_dimension = image.columns
    else
      center = 0
      center = find_center_of_objects(center, file_path, :y)
      crop_dimension = TARGET_HEIGHT
      contrained_dimension = image.rows
    end

    half_crop_dimension = crop_dimension / 2
    point = center - half_crop_dimension

    if point <= 0
      point = 0
    elsif point + half_crop_dimension > contrained_dimension
      point = contrained_dimension - crop_dimension
    end

    x = 0
    y = 0
    if panoramic?
      x = point
    else
      y = point
    end

    {x: x, y: y, width: TARGET_WIDTH, height: TARGET_HEIGHT}
  end

  def find_center_of_objects(center, file_path, dimension)
    image = OpenCV::CvMat.load(file_path)

    objects = DETECTOR.detect_objects(image)
    if objects.count > 0
      center = 0
      objects.each do |region|
        center += region.center.send(dimension)
      end
      center = center / objects.count.to_f
    end
    center
  end

end