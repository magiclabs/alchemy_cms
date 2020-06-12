# frozen_string_literal: true

require "forwardable"

module Alchemy
  # Represents a rendered picture
  #
  # Resizes, crops and encodes the image with imagemagick
  #
  class PictureVariant
    extend Forwardable

    include Alchemy::Logger
    include Alchemy::Picture::Transformations

    attr_reader :picture

    def_delegators :@picture,
      :image_file,
      :image_file_width,
      :image_file_height,
      :image_file_name,
      :image_file_size

    # @param [Alchemy::Picture]
    #
    def initialize(picture)
      raise ArgumentError, "Picture missing!" if picture.nil?

      @picture = picture
    end

    # Get a variant of given picture
    #
    # @param [Hash] options passed to the image processor
    # @option options [Boolean] :crop Pass true to enable cropping
    # @option options [String] :crop_from Coordinates to start cropping from
    # @option options [String] :crop_size Size of the cropping area
    # @option options [Boolean] :flatten Pass true to flatten GIFs
    # @option options [String|Symbol] :format Image format to encode the image in
    # @option options [Integer] :quality JPEG compress quality
    # @option options [String] :size Size of resulting image in WxH
    # @option options [Boolean] :upsample Pass true to upsample (grow) an image if the original size is lower than the resulting size
    #
    # @return [Dragonfly::Attachment] The processed image variant
    #
    def call(options = {})
      image = image_file

      raise MissingImageFileError, "Missing image file for #{picture.inspect}" if image.nil?

      image = processed_image(image, options)
      image = encoded_image(image, options)
      image
    rescue MissingImageFileError, WrongImageFormatError => e
      log_warning e.message
      nil
    end

    private

    # Returns the processed image dependent of size and cropping parameters
    def processed_image(image, options = {})
      size = options[:size]
      upsample = !!options[:upsample]

      return image unless size.present? && picture.has_convertible_format?

      if options[:crop]
        crop(size, options[:crop_from], options[:crop_size], upsample)
      else
        resize(size, upsample)
      end
    end

    # Returns the encoded image
    #
    # Flatten animated gifs, only if converting to a different format.
    # Can be overwritten via +options[:flatten]+.
    #
    def encoded_image(image, options = {})
      target_format = options[:format] || picture.default_render_format

      unless target_format.in?(Alchemy::Picture.allowed_filetypes)
        raise WrongImageFormatError.new(self, target_format)
      end

      options = {
        flatten: target_format != "gif" && picture.image_file_format == "gif",
      }.with_indifferent_access.merge(options)

      encoding_options = []

      convert_format = target_format != picture.image_file_format.sub("jpeg", "jpg")

      if target_format =~ /jpe?g/ && convert_format
        quality = options[:quality] || Config.get(:output_image_jpg_quality)
        encoding_options << "-quality #{quality}"
      end

      if options[:flatten]
        encoding_options << "-flatten"
      end

      convertion_needed = convert_format || encoding_options.present?

      if picture.has_convertible_format? && convertion_needed
        image = image.encode(target_format, encoding_options.join(" "))
      end

      image
    end
  end
end