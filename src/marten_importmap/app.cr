require "./configuration"
require "./template/**"

module MartenImportmap
  class App < Marten::App
    label "importmap"

    def setup
      ImportMap.resolver = ->(path : String) { Marten.assets.url(path) }
      Marten::Template::Tag.register "importmap", Template::Tag::ImportMapTag
    end
  end
end
