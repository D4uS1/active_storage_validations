# frozen_string_literal: true

require_relative 'metadata.rb'

module ActiveStorageValidations
  class AspectRatioValidator < ActiveModel::EachValidator # :nodoc
    include OptionProcUnfolding

    AVAILABLE_CHECKS = %i[with].freeze
    PRECISION = 3

    def initialize(options)
      require 'mini_magick' unless defined?(MiniMagick)
      super
    end


    def check_validity!
      return true if AVAILABLE_CHECKS.any? { |argument| options.key?(argument) }
      raise ArgumentError, 'You must pass "aspect_ratio: :OPTION" option to the validator'
    end

    if Rails.gem_version >= Gem::Version.new('6.0.0')
      def validate_each(record, attribute, _value)
        return true unless record.send(attribute).attached?

        changes = record.attachment_changes[attribute.to_s]
        return true if changes.blank?

        options = self.options.merge(AVAILABLE_CHECKS.each_with_object(Hash.new) {|k, o| o[k] = self.options[k].call(record) if self.options[k].is_a?(Proc)})
        files = Array.wrap(changes.is_a?(ActiveStorage::Attached::Changes::CreateMany) ? changes.attachables : changes.attachable)

        files.each do |file|
          metadata = Metadata.new(file).metadata
          next if is_valid?(record, attribute, metadata, options)
          break
        end
      end
    else
      # Rails 5
      def validate_each(record, attribute, _value)
        return true unless record.send(attribute).attached?
  
        options = self.options.merge(AVAILABLE_CHECKS.each_with_object(Hash.new) {|k, o| o[k] = self.options[k].call(record) if self.options[k].is_a?(Proc)})
        files = Array.wrap(record.send(attribute))
  
        files.each do |file|
          # Analyze file first if not analyzed to get all required metadata.
          file.analyze; file.reload unless file.analyzed?
          metadata = file.metadata
  
          next if is_valid?(record, attribute, metadata, options)
          break
        end
      end
    end


    private


    def is_valid?(record, attribute, metadata, options)
      if metadata[:width].to_i <= 0 || metadata[:height].to_i <= 0
        add_error(record, attribute, options[:message].presence || :image_metadata_missing, options[:with])
        return false
      end

      case options[:with]
      when :square
        return true if metadata[:width] == metadata[:height]
        add_error(record, attribute, :aspect_ratio_not_square, options[:with])

      when :portrait
        return true if metadata[:height] > metadata[:width]
        add_error(record, attribute, :aspect_ratio_not_portrait, options[:with])

      when :landscape
        return true if metadata[:width] > metadata[:height]
        add_error(record, attribute, :aspect_ratio_not_landscape, options[:with])

      else
        if options[:with] =~ /is\_(\d*)\_(\d*)/
          x = $1.to_i
          y = $2.to_i

          return true if (x.to_f / y).round(PRECISION) == (metadata[:width].to_f / metadata[:height]).round(PRECISION)

          add_error(record, attribute, :aspect_ratio_is_not, "#{x}x#{y}")
        else
          add_error(record, attribute, :aspect_ratio_unknown, options[:with])
        end
      end
      false
    end


    def add_error(record, attribute, type, interpolate)
      key = options[:message].presence || type
      return if record.errors.added?(attribute, key)
      record.errors.add(attribute, key, aspect_ratio: interpolate)
    end

  end
end
