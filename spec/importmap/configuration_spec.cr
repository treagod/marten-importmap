require "../spec_helper"

describe MartenImportmap::Configuration do
  describe "#draw" do
    it "allows defining entries through the ImportMap manager" do
      config = MartenImportmap::Configuration.new

      config.draw do
        pin "application", "application.js"
      end

      output = ImportMap.tag(entrypoint: "application")
      output.should contain "\"application\":\"application.js\""
    end

    it "exposes the full ImportMap DSL within the draw block" do
      config = MartenImportmap::Configuration.new

      config.draw do
        namespace "admin" do
          pin "charts", "admin/charts.js"
        end
      end

      output = ImportMap.tag("admin", entrypoint: "charts")
      output.should contain "data-namespace=\"admin\""
      output.should contain "\"charts\":\"admin/charts.js\""
    end
  end
end
