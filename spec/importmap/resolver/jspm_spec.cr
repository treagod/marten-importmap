require "../../spec_helper"

describe MartenImportmap::Resolver::Provider do
  describe ".from_cli" do
    it "recognizes known provider aliases" do
      MartenImportmap::Resolver::Provider.from_cli("jspm").should eq MartenImportmap::Resolver::Provider::JspmIo
      MartenImportmap::Resolver::Provider.from_cli("jsdelivr").should eq MartenImportmap::Resolver::Provider::Jsdelivr
      MartenImportmap::Resolver::Provider.from_cli("esm.sh").should eq MartenImportmap::Resolver::Provider::EsmSh
    end

    it "returns nil for unsupported providers" do
      MartenImportmap::Resolver::Provider.from_cli("unknown").should be_nil
    end
  end
end

describe MartenImportmap::Resolver::Jspm do
  describe ".pin_key_guess" do
    it "removes unscoped package versions" do
      MartenImportmap::Resolver::Jspm.pin_key_guess("react@18.2.0").should eq "react"
    end

    it "removes scoped package versions while preserving subpaths" do
      MartenImportmap::Resolver::Jspm.pin_key_guess("@hotwired/stimulus@3.2.2/loading").should eq "@hotwired/stimulus/loading"
    end
  end
end
