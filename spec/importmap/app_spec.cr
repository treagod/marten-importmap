require "../spec_helper"

describe MartenImportmap::App do
  describe "#setup" do
    it "registers the importmap template tag" do
      MartenImportmap::App.new.setup

      Marten::Template::Tag.registry["importmap"].should eq MartenImportmap::Template::Tag::ImportMapTag
    end

    it "sets the ImportMap resolver so relative paths leverage Marten assets" do
      MartenImportmap::App.new.setup

      ImportMap.draw do
        pin "application", "application.js", preload: false
      end

      output = ImportMap.tag(entrypoint: "application")
      output.should contain "/assets/application.js"
      output.should contain %(<script type="module">import "application"</script>)
    end

    it "allows rendering the importmap tag inside Marten templates" do
      MartenImportmap::App.new.setup

      ImportMap.draw do
        pin "application", "application.js", preload: false
      end

      template = Marten::Template::Template.new("{% importmap %}")
      output = template.render

      output.should contain "<script type=\"importmap\">"
      output.should contain "/assets/application.js"
      output.should contain %(<script type="module">import "application"</script>)
    end
  end
end
