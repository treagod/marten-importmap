module MartenImportmap
  class Configuration < Marten::Conf::Settings
    namespace :importmap

    property? keep_cdn_urls : Bool = false
    property vendor_scripts_dir : String = "src/assets/vendor/"

    def draw(&)
      with ImportMap::Manager.instance yield
    end
  end
end
