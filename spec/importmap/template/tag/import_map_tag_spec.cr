require "../../../spec_helper"

private def build_tag(markup)
  parser = Marten::Template::Parser.new("")
  Importmap::Template::Tag::ImportMapTag.new(parser, markup)
end

describe Importmap::Template::Tag::ImportMapTag do
  describe "::new" do
    it "raises when the entrypoint argument is missing the entrypoint: prefix" do
      expect_raises(Marten::Template::Errors::InvalidSyntax) do
        build_tag("importmap app dashboard")
      end
    end

    it "raises when more than two arguments are provided" do
      expect_raises(Marten::Template::Errors::InvalidSyntax) do
        build_tag("importmap app entrypoint:dashboard extra")
      end
    end
  end

  describe "#render" do
    it "renders the base import map when no namespace was provided" do
      ImportMap.draw do
        pin "application", "application.js"
      end

      output = build_tag("importmap").render(Marten::Template::Context.new)

      output.should contain "<script type=\"importmap\">"
      output.should contain "\"application\":\"application.js\""
      output.should contain %(<script type="module">import "application"</script>)
    end

    it "renders the requested namespace map" do
      ImportMap.draw do
        pin "application", "application.js"
        namespace "admin" do
          pin "charts", "admin/charts.js"
        end
      end

      output = build_tag("importmap 'admin'").render(Marten::Template::Context.new)

      output.should contain "data-namespace=\"admin\""
      output.should contain "\"charts\":\"admin/charts.js\""
    end

    it "supports setting a custom entrypoint" do
      ImportMap.draw do
        pin "application", "application.js"
        namespace "dashboard" do
          pin "main", "dashboard/main.js"
        end
      end

      output = build_tag("importmap 'dashboard' entrypoint:'dashboard/main'").render(
        Marten::Template::Context.new
      )

      output.should contain %(<script type="module">import "dashboard/main"</script>)
    end

    it "evaluates namespace and entrypoint expressions from the context" do
      ImportMap.draw do
        pin "application", "application.js"
        namespace "customers" do
          pin "reports", "customers/reports.js"
        end
      end

      context = Marten::Template::Context{"ns" => "customers", "ep" => "customers/reports"}

      output = build_tag("importmap ns entrypoint:ep").render(context)

      output.should contain "data-namespace=\"customers\""
      output.should contain %(<script type="module">import "customers/reports"</script>)
    end
  end
end
