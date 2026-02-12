require "../../../../spec_helper"

module MartenImportmap::CLI::Manage::Command::ImportmapSpec
  class TestImportmapCommand < MartenImportmap::CLI::Manage::Command::Importmap
    @@downloads = [] of Tuple(String, String)
    @@response : MartenImportmap::Resolver::GenerateResponse? = nil

    def self.downloads
      @@downloads
    end

    def self.reset!
      @@downloads = [] of Tuple(String, String)
      @@response = nil
    end

    def self.response=(response : MartenImportmap::Resolver::GenerateResponse)
      @@response = response
    end

    protected def resolve_library(_library : String, _provider : MartenImportmap::Resolver::Provider)
      @@response.not_nil!
    end

    protected def download_file(url : String, target_path : String)
      @@downloads << {url, target_path}
    end
  end
end

describe MartenImportmap::CLI::Manage::Command::Importmap do
  around_each do |test|
    settings = Marten.settings.importmap.as(MartenImportmap::Configuration)
    previous_keep_cdn_urls = settings.keep_cdn_urls?
    previous_vendor_scripts_dir = settings.vendor_scripts_dir

    settings.keep_cdn_urls = false
    settings.vendor_scripts_dir = "src/assets/vendor_specs/"
    MartenImportmap::CLI::Manage::Command::ImportmapSpec::TestImportmapCommand.reset!

    test.run
  ensure
    restored_settings = Marten.settings.importmap.as(MartenImportmap::Configuration)
    restored_settings.keep_cdn_urls = previous_keep_cdn_urls || false
    restored_settings.vendor_scripts_dir = previous_vendor_scripts_dir || "src/assets/vendor/"
  end

  describe "::command_name" do
    it "is exposed as the importmap command" do
      MartenImportmap::CLI::Manage::Command::Importmap.command_name.should eq "importmap"
    end
  end

  describe "#run" do
    it "supports the pin subcommand and outputs Crystal pin lines" do
      stdout = IO::Memory.new
      stderr = IO::Memory.new

      response = MartenImportmap::Resolver::GenerateResponse.from_json(
        %({"map":{"imports":{"react":"https://cdn.example/react.js","react/jsx-runtime":"https://cdn.example/react-jsx-runtime.js"}}})
      )
      MartenImportmap::CLI::Manage::Command::ImportmapSpec::TestImportmapCommand.response = response

      command = MartenImportmap::CLI::Manage::Command::ImportmapSpec::TestImportmapCommand.new(
        options: ["pin", "react", "--from", "jsdelivr"],
        stdout: stdout,
        stderr: stderr
      )

      command.handle

      output = stdout.rewind.gets_to_end

      output.includes?("config.importmap.draw do").should be_true
      output.includes?(%(pin "react", "vendor_specs/react.js")).should be_true
      output.includes?(%(pin "react/jsx-runtime", "vendor_specs/react/jsx-runtime.js")).should be_true
      output.includes?("end").should be_true

      MartenImportmap::CLI::Manage::Command::ImportmapSpec::TestImportmapCommand.downloads.size.should eq 2
      stderr.rewind.gets_to_end.should be_empty
    end

    it "fails when no subcommand is provided" do
      stdout = IO::Memory.new
      stderr = IO::Memory.new

      command = MartenImportmap::CLI::Manage::Command::ImportmapSpec::TestImportmapCommand.new(
        options: [] of String,
        stdout: stdout,
        stderr: stderr,
        exit_raises: true
      )

      error = expect_raises(Marten::CLI::Manage::Errors::Exit) do
        command.handle!
      end

      error.code.should eq 1
      stderr.rewind.gets_to_end.includes?("Please provide an importmap subcommand").should be_true
    end

    it "fails when the subcommand is not supported" do
      stdout = IO::Memory.new
      stderr = IO::Memory.new

      command = MartenImportmap::CLI::Manage::Command::ImportmapSpec::TestImportmapCommand.new(
        options: ["unpin", "react"],
        stdout: stdout,
        stderr: stderr,
        exit_raises: true
      )

      error = expect_raises(Marten::CLI::Manage::Errors::Exit) do
        command.handle!
      end

      error.code.should eq 1
      stderr.rewind.gets_to_end.includes?("Unsupported importmap subcommand 'unpin'").should be_true
    end

    it "fails when the pin library is missing" do
      stdout = IO::Memory.new
      stderr = IO::Memory.new

      command = MartenImportmap::CLI::Manage::Command::ImportmapSpec::TestImportmapCommand.new(
        options: ["pin"],
        stdout: stdout,
        stderr: stderr,
        exit_raises: true
      )

      error = expect_raises(Marten::CLI::Manage::Errors::Exit) do
        command.handle!
      end

      error.code.should eq 1
      stderr.rewind.gets_to_end.includes?("Please provide a JavaScript library to pin").should be_true
    end

    it "fails when the provider is not supported" do
      stdout = IO::Memory.new
      stderr = IO::Memory.new

      command = MartenImportmap::CLI::Manage::Command::ImportmapSpec::TestImportmapCommand.new(
        options: ["pin", "react", "--from", "bad-cdn"],
        stdout: stdout,
        stderr: stderr,
        exit_raises: true
      )

      error = expect_raises(Marten::CLI::Manage::Errors::Exit) do
        command.handle!
      end

      error.code.should eq 1
      stderr.rewind.gets_to_end.includes?("Unsupported provider 'bad-cdn'").should be_true
    end

    it "keeps CDN URLs when configured to do so" do
      settings = Marten.settings.importmap.as(MartenImportmap::Configuration)
      settings.keep_cdn_urls = true

      stdout = IO::Memory.new
      stderr = IO::Memory.new

      response = MartenImportmap::Resolver::GenerateResponse.from_json(
        %({"map":{"imports":{"react":"https://cdn.example/react.js"}}})
      )
      MartenImportmap::CLI::Manage::Command::ImportmapSpec::TestImportmapCommand.response = response

      command = MartenImportmap::CLI::Manage::Command::ImportmapSpec::TestImportmapCommand.new(
        options: ["pin", "react"],
        stdout: stdout,
        stderr: stderr
      )

      command.handle

      output = stdout.rewind.gets_to_end
      output.includes?(%(pin "react", "https://cdn.example/react.js")).should be_true
      MartenImportmap::CLI::Manage::Command::ImportmapSpec::TestImportmapCommand.downloads.should be_empty
      stderr.rewind.gets_to_end.should be_empty
    end
  end
end
