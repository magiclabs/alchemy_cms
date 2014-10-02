module Alchemy
  module Admin
    class LanguagesController < Alchemy::Admin::ResourcesController
      respond_to :json

      def index
        @language.page_layout = (configured_page_layout or @language.page_layout)
        render_with_protection @language.to_json
      end

      def new
        @language = Alchemy::Language.new
        @language.page_layout = (configured_page_layout or @language.page_layout)
      end

    protected

      def configured_page_layout
        Alchemy::Config.get(:default_language).try('[]', 'page_layout')
      end

    end
  end
end
