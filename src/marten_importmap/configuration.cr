module MartenImportmap
  class Configuration < Marten::Conf::Settings
    namespace :importmap

    def draw(&)
      with ImportMap::Manager.instance yield
    end
  end
end
