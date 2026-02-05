require "../spec_helper"

describe Importmap::Configuration do
  describe "#draw" do
    it "allows defining entries through the ImportMap manager" do
      config = Importmap::Configuration.new

      config.draw do
        pin "application", "application.js"
      end

      output = ImportMap.tag(entrypoint: "application")
      output.should contain "\"application\":\"application.js\""
    end
  end
end
