module HasTranslatedFields
  module ActiveRecord
    def self.included(base)
      super
      base.extend ClassMethods
      class << base
        attr_accessor :has_translated_fields_options
      end
    end

    module ClassMethods
      def self.inherited(klass)
        super
        klass.extend(ActsAs)
        class << klass
          attr_accessor :has_translated_fields_options
        end
      end

      def has_translated_fields(*fields)
        self.has_translated_fields_options=fields
        extend ClassMethods
        self.create_missing_translated_field_columns
        self.create_missing_translated_field_readers
      end

      def translated_fields_for(*fields)
        fields.flatten.map {|field| ::I18n.available_locales.map{|locale| "#{field}_#{locale}"} }.flatten
      end

      def create_missing_translated_field_columns
        has_translated_fields_options.each do |translated_field|
          ::I18n.available_locales.each do |locale|
            db_field="#{translated_field}_#{locale}"
            default_db_field="#{translated_field}_#{::I18n.default_locale}"
            unless column_names.include?(db_field)
              Rails.logger.info "has_translated_fields is adding #{db_field} to #{name}"
              klass=self
              ::ActiveRecord::Schema.define do
                add_column klass.table_name, db_field, klass.columns.find{|c|c.name==default_db_field}.type
              end
              klass.reset_column_information
            end
          end
        end

        def create_missing_translated_field_readers
          has_translated_fields_options.each do |translated_field|
            define_method(translated_field) do
              chosen_locale = nil
              chosen_translation = nil
              [::I18n.locale, ::I18n.default_locale, ::I18n.available_locales].flatten.uniq.find do |locale|
                method = "#{translated_field}_#{locale}"
                if self.respond_to?(method)
                  result = self.send(method)
                  if result.present?
                    chosen_locale = locale
                    chosen_translation = result
                    next true
                  end
                end
              end
              if chosen_translation
                chosen_translation.metaclass.send(:include, LocalizedString)
                chosen_translation.locale = chosen_locale
                chosen_translation.fallback = (chosen_locale != ::I18n.locale)
              end
              chosen_translation
            end
          end
        end
      end
    end
  end
  module LocalizedString
    attr_accessor :locale, :fallback
    alias_method :fallback?, :fallback
  end
  module I18n
    module Backend
      module AnyTranslation

        protected

        # Will do a lookup in the preferred locale, then fall back to the default,
        # then to any other available locale with a translation.
        #
        # Looks up a translation from the translations hash. Returns nil if
        # eiher key is nil, or locale, scope or key do not exist as a key in the
        # nested translations hash. Splits keys or scopes containing dots
        # into multiple keys, i.e. <tt>currency.format</tt> is regarded the same as
        # <tt>%w(currency format)</tt>.
        #
        # The returned translation includes the LocalizedString module, offering +locale+ and +fallback?+:
        #   I18n.locale = :nl
        #   str = I18n.t("bla") # => "blah"
        #   str.locale    # => :en
        #   str.fallback? # => true
        def lookup(locale, key, scope = [], options = {})
          possible_locales = [locale, ::I18n.default_locale, ::I18n.available_locales].flatten.uniq
          possible_locales.each do |possible_locale|
            next unless translation = super(possible_locale, key, scope, options)
            translation.metaclass.send(:include, LocalizedString)
            translation.locale = possible_locale
            translation.fallback = (possible_locale != locale)
            return translation
          end
          nil
        end
      end
    end
  end
end

ActiveRecord::Base.send(:include, HasTranslatedFields::ActiveRecord)
I18n::Backend::Simple.send(:include, HasTranslatedFields::I18n::Backend::AnyTranslation)