module ImportMap
  class Manager
    def reset_for_specs!
      @base = Map.new
      @namespace = {} of String => Map
      @cache = {} of String? => Tuple(String, Array(String))
      @resolver = ->(path : String) { path }
    end
  end
end

def reset_import_map
  ImportMap::Manager.instance.reset_for_specs!
end
