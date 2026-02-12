require "../spec_helper"

describe MartenImportmap::Configuration do
  describe "#keep_cdn_urls?" do
    it "defaults to downloading and vendoring resolved scripts" do
      config = MartenImportmap::Configuration.new

      (config.keep_cdn_urls? || false).should be_false
    end

    it "can be configured to keep CDN URLs" do
      config = MartenImportmap::Configuration.new

      config.keep_cdn_urls = true

      (config.keep_cdn_urls? || false).should be_true
    end
  end

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

  describe "#vendor_scripts_dir" do
    it "defaults to the importmap vendor scripts directory" do
      config = MartenImportmap::Configuration.new

      config.vendor_scripts_dir.should eq "src/assets/vendor/"
    end

    it "can be customized" do
      config = MartenImportmap::Configuration.new

      config.vendor_scripts_dir = "src/assets/vendor/"

      config.vendor_scripts_dir.should eq "src/assets/vendor/"
    end
  end
end
