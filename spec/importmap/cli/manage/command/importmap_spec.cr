require "../../../../spec_helper"
require "file_utils"

module MartenImportmap::CLI::Manage::Command::ImportmapSpec
  class TestImportmapCommand < MartenImportmap::CLI::Manage::Command::Importmap
    DEFAULT_PROJECT_CONTENT = <<-CRYSTAL
      # Third party requirements.
      require "marten"

      # Configuration requirements.
      require "../config/settings/base"
      require "../config/settings/**"
      require "../config/initializers/**"
      require "../config/routes"
      CRYSTAL

    DEFAULT_SETTINGS_CONTENT = <<-CRYSTAL
      Marten.configure do |config|
        config.installed_apps = [] of Marten::Apps::Config.class
      end
      CRYSTAL

    @@downloads = [] of Tuple(String, String)
    @@response : MartenImportmap::Resolver::GenerateResponse? = nil
    @@project_root = File.join(Dir.tempdir, "marten_importmap_spec_project")

    def self.downloads
      @@downloads
    end

    def self.project_root
      @@project_root
    end

    def self.project_file_path
      File.join(@@project_root, "src/project.cr")
    end

    def self.settings_file_path
      File.join(@@project_root, "config/settings/base.cr")
    end

    def self.manual_initializer_path
      File.join(@@project_root, "config/initializers/importmap.cr")
    end

    def self.generated_initializer_path
      File.join(@@project_root, "config/initializers/importmap_pins.cr")
    end

    def self.cli_file_path
      File.join(@@project_root, "src/cli.cr")
    end

    def self.starter_js_path
      File.join(@@project_root, "src/assets/application.js")
    end

    def self.reset!
      @@downloads = [] of Tuple(String, String)
      @@response = nil
      prepare_project!
    end

    def self.prepare_project!(
      project_content : String = DEFAULT_PROJECT_CONTENT,
      settings_content : String = DEFAULT_SETTINGS_CONTENT,
      manual_initializer_content : String? = nil,
      generated_initializer_content : String? = nil,
      starter_js_content : String? = nil,
      cli_content : String? = nil,
    )
      FileUtils.rm_rf(@@project_root)

      Dir.mkdir_p(File.dirname(project_file_path))
      Dir.mkdir_p(File.dirname(settings_file_path))

      File.write(project_file_path, project_content)
      File.write(settings_file_path, settings_content)

      if manual_initializer_content
        Dir.mkdir_p(File.dirname(manual_initializer_path))
        File.write(manual_initializer_path, manual_initializer_content)
      end

      if generated_initializer_content
        Dir.mkdir_p(File.dirname(generated_initializer_path))
        File.write(generated_initializer_path, generated_initializer_content)
      end

      if starter_js_content
        Dir.mkdir_p(File.dirname(starter_js_path))
        File.write(starter_js_path, starter_js_content)
      end

      if cli_content
        Dir.mkdir_p(File.dirname(cli_file_path))
        File.write(cli_file_path, cli_content)
      end
    end

    def self.response=(response : MartenImportmap::Resolver::GenerateResponse)
      @@response = response
    end

    protected def resolve_library(_library : String, _provider : MartenImportmap::Resolver::Provider)
      response = @@response
      raise "No mocked resolver response configured for the test command" if response.nil?

      response
    end

    protected def download_file(url : String, target_path : String)
      @@downloads << {url, target_path}
    end

    protected def project_root : Path
      Path.new(@@project_root)
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
    it "supports the init subcommand and bootstraps the project files" do
      stdout = IO::Memory.new
      stderr = IO::Memory.new

      command = MartenImportmap::CLI::Manage::Command::ImportmapSpec::TestImportmapCommand.new(
        options: ["init"],
        stdout: stdout,
        stderr: stderr
      )

      command.handle

      output = stdout.rewind.gets_to_end
      output.includes?("Initializing importmap support:").should be_true
      output.includes?("DONE").should be_true

      project_content = File.read(MartenImportmap::CLI::Manage::Command::ImportmapSpec::TestImportmapCommand.project_file_path)
      project_content.includes?(%(require "marten_importmap")).should be_true

      settings_content = File.read(MartenImportmap::CLI::Manage::Command::ImportmapSpec::TestImportmapCommand.settings_file_path)
      settings_content.includes?("MartenImportmap::App").should be_true

      manual_initializer_path = MartenImportmap::CLI::Manage::Command::ImportmapSpec::TestImportmapCommand.manual_initializer_path
      manual_content = File.read(manual_initializer_path)
      manual_content.includes?("Marten.configure do |config|").should be_true
      manual_content.includes?("config.importmap.draw do").should be_true
      manual_content.includes?(%(pin "application", "application.js")).should be_true
      manual_content.includes?("ImportMap.draw").should be_false

      generated_initializer_path = MartenImportmap::CLI::Manage::Command::ImportmapSpec::TestImportmapCommand.generated_initializer_path
      generated_content = File.read(generated_initializer_path)
      generated_content.includes?("# AUTO-GENERATED by `marten importmap pin ...`").should be_true
      generated_content.includes?("Marten.configure do |config|").should be_true
      generated_content.includes?("config.importmap.draw do").should be_true

      starter_js = File.read(MartenImportmap::CLI::Manage::Command::ImportmapSpec::TestImportmapCommand.starter_js_path)
      starter_js.should eq "// Importmap entrypoint.\n"

      stderr.rewind.gets_to_end.should be_empty
    end

    it "skips init steps when the project is already initialized" do
      stdout = IO::Memory.new
      stderr = IO::Memory.new

      first_command = MartenImportmap::CLI::Manage::Command::ImportmapSpec::TestImportmapCommand.new(
        options: ["init"],
        stdout: stdout,
        stderr: stderr
      )
      first_command.handle

      manual_before = File.read(MartenImportmap::CLI::Manage::Command::ImportmapSpec::TestImportmapCommand.manual_initializer_path)
      generated_before = File.read(MartenImportmap::CLI::Manage::Command::ImportmapSpec::TestImportmapCommand.generated_initializer_path)

      stdout = IO::Memory.new
      second_command = MartenImportmap::CLI::Manage::Command::ImportmapSpec::TestImportmapCommand.new(
        options: ["init"],
        stdout: stdout,
        stderr: stderr
      )
      second_command.handle

      output = stdout.rewind.gets_to_end
      output.includes?("SKIPPED").should be_true
      File.read(MartenImportmap::CLI::Manage::Command::ImportmapSpec::TestImportmapCommand.manual_initializer_path).should eq manual_before
      File.read(MartenImportmap::CLI::Manage::Command::ImportmapSpec::TestImportmapCommand.generated_initializer_path).should eq generated_before
      stderr.rewind.gets_to_end.should be_empty
    end

    it "does not overwrite an existing manual initializer during init" do
      custom_initializer = <<-CRYSTAL
        Marten.configure do |config|
          config.importmap.draw do
            namespace "admin" do
              pin "charts", "admin/charts.js"
            end
          end
        end
        CRYSTAL

      MartenImportmap::CLI::Manage::Command::ImportmapSpec::TestImportmapCommand.prepare_project!(
        manual_initializer_content: custom_initializer
      )

      stdout = IO::Memory.new
      stderr = IO::Memory.new

      command = MartenImportmap::CLI::Manage::Command::ImportmapSpec::TestImportmapCommand.new(
        options: ["init"],
        stdout: stdout,
        stderr: stderr
      )

      command.handle

      output = stdout.rewind.gets_to_end
      output.includes?("SKIPPED").should be_true
      File.read(MartenImportmap::CLI::Manage::Command::ImportmapSpec::TestImportmapCommand.manual_initializer_path).should eq custom_initializer
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

    it "requires init before pinning packages" do
      stdout = IO::Memory.new
      stderr = IO::Memory.new

      response = MartenImportmap::Resolver::GenerateResponse.from_json(
        %({"map":{"imports":{"react":"https://cdn.example/react.js"}}})
      )
      MartenImportmap::CLI::Manage::Command::ImportmapSpec::TestImportmapCommand.response = response

      command = MartenImportmap::CLI::Manage::Command::ImportmapSpec::TestImportmapCommand.new(
        options: ["pin", "react"],
        stdout: stdout,
        stderr: stderr,
        exit_raises: true
      )

      error = expect_raises(Marten::CLI::Manage::Errors::Exit) do
        command.handle!
      end

      error.code.should eq 1
      stderr.rewind.gets_to_end.includes?("Please run `marten importmap init` first").should be_true
    end

    it "supports the pin subcommand and writes the generated pins initializer file" do
      stdout = IO::Memory.new
      stderr = IO::Memory.new

      init_command = MartenImportmap::CLI::Manage::Command::ImportmapSpec::TestImportmapCommand.new(
        options: ["init"],
        stdout: stdout,
        stderr: stderr
      )
      init_command.handle

      manual_initializer_path = MartenImportmap::CLI::Manage::Command::ImportmapSpec::TestImportmapCommand.manual_initializer_path
      manual_before = File.read(manual_initializer_path)

      response = MartenImportmap::Resolver::GenerateResponse.from_json(
        %({"map":{"imports":{"react":"https://cdn.example/react.js","react/jsx-runtime":"https://cdn.example/react-jsx-runtime.js"}}})
      )
      MartenImportmap::CLI::Manage::Command::ImportmapSpec::TestImportmapCommand.response = response

      stdout = IO::Memory.new
      command = MartenImportmap::CLI::Manage::Command::ImportmapSpec::TestImportmapCommand.new(
        options: ["pin", "react", "--from", "jsdelivr"],
        stdout: stdout,
        stderr: stderr
      )

      command.handle

      output = stdout.rewind.gets_to_end
      generated_initializer_path = MartenImportmap::CLI::Manage::Command::ImportmapSpec::TestImportmapCommand.generated_initializer_path
      output.includes?("Updated #{generated_initializer_path} with 2 pins").should be_true

      content = File.read(generated_initializer_path)
      content.includes?("# AUTO-GENERATED by `marten importmap pin ...`").should be_true
      content.includes?(%(Marten.configure do |config|)).should be_true
      content.includes?(%(pin "react", "vendor_specs/react.js")).should be_true
      content.includes?(%(pin "react/jsx-runtime", "vendor_specs/react/jsx-runtime.js")).should be_true

      File.read(manual_initializer_path).should eq manual_before
      MartenImportmap::CLI::Manage::Command::ImportmapSpec::TestImportmapCommand.downloads.size.should eq 2
      stderr.rewind.gets_to_end.should be_empty
    end

    it "keeps CDN URLs when configured to do so" do
      settings = Marten.settings.importmap.as(MartenImportmap::Configuration)
      settings.keep_cdn_urls = true

      stdout = IO::Memory.new
      stderr = IO::Memory.new

      init_command = MartenImportmap::CLI::Manage::Command::ImportmapSpec::TestImportmapCommand.new(
        options: ["init"],
        stdout: stdout,
        stderr: stderr
      )
      init_command.handle

      response = MartenImportmap::Resolver::GenerateResponse.from_json(
        %({"map":{"imports":{"react":"https://cdn.example/react.js"}}})
      )
      MartenImportmap::CLI::Manage::Command::ImportmapSpec::TestImportmapCommand.response = response

      stdout = IO::Memory.new
      command = MartenImportmap::CLI::Manage::Command::ImportmapSpec::TestImportmapCommand.new(
        options: ["pin", "react"],
        stdout: stdout,
        stderr: stderr
      )

      command.handle

      output = stdout.rewind.gets_to_end
      output.includes?("Updated").should be_true
      generated_initializer_path = MartenImportmap::CLI::Manage::Command::ImportmapSpec::TestImportmapCommand.generated_initializer_path
      File.read(generated_initializer_path).includes?(%(pin "react", "https://cdn.example/react.js")).should be_true
      MartenImportmap::CLI::Manage::Command::ImportmapSpec::TestImportmapCommand.downloads.should be_empty
      stderr.rewind.gets_to_end.should be_empty
    end

    it "merges new pins into the existing generated initializer file" do
      stdout = IO::Memory.new
      stderr = IO::Memory.new

      init_command = MartenImportmap::CLI::Manage::Command::ImportmapSpec::TestImportmapCommand.new(
        options: ["init"],
        stdout: stdout,
        stderr: stderr
      )
      init_command.handle

      initial_response = MartenImportmap::Resolver::GenerateResponse.from_json(
        %({"map":{"imports":{"react":"https://cdn.example/react.js"}}})
      )
      MartenImportmap::CLI::Manage::Command::ImportmapSpec::TestImportmapCommand.response = initial_response

      first_command = MartenImportmap::CLI::Manage::Command::ImportmapSpec::TestImportmapCommand.new(
        options: ["pin", "react"],
        stdout: stdout,
        stderr: stderr
      )
      first_command.handle

      second_response = MartenImportmap::Resolver::GenerateResponse.from_json(
        %({"map":{"imports":{"vue":"https://cdn.example/vue.js"}}})
      )
      MartenImportmap::CLI::Manage::Command::ImportmapSpec::TestImportmapCommand.response = second_response

      second_command = MartenImportmap::CLI::Manage::Command::ImportmapSpec::TestImportmapCommand.new(
        options: ["pin", "vue"],
        stdout: stdout,
        stderr: stderr
      )
      second_command.handle

      content = File.read(MartenImportmap::CLI::Manage::Command::ImportmapSpec::TestImportmapCommand.generated_initializer_path)
      content.includes?(%(pin "react", "vendor_specs/react.js")).should be_true
      content.includes?(%(pin "vue", "vendor_specs/vue.js")).should be_true
    end

    it "adds require marten_importmap/cli to src/cli.cr when the file exists" do
      cli_content = %(# Marten CLI requirement.\nrequire "marten/cli"\n\n# Third party CLI requirements.\n)

      MartenImportmap::CLI::Manage::Command::ImportmapSpec::TestImportmapCommand.prepare_project!(
        cli_content: cli_content
      )

      stdout = IO::Memory.new
      stderr = IO::Memory.new

      command = MartenImportmap::CLI::Manage::Command::ImportmapSpec::TestImportmapCommand.new(
        options: ["init"],
        stdout: stdout,
        stderr: stderr
      )

      command.handle

      result = File.read(MartenImportmap::CLI::Manage::Command::ImportmapSpec::TestImportmapCommand.cli_file_path)
      result.includes?(%(require "marten_importmap/cli")).should be_true
      stderr.rewind.gets_to_end.should be_empty
    end

    it "skips the cli.cr step when src/cli.cr does not exist" do
      stdout = IO::Memory.new
      stderr = IO::Memory.new

      command = MartenImportmap::CLI::Manage::Command::ImportmapSpec::TestImportmapCommand.new(
        options: ["init"],
        stdout: stdout,
        stderr: stderr
      )

      command.handle

      File.exists?(MartenImportmap::CLI::Manage::Command::ImportmapSpec::TestImportmapCommand.cli_file_path).should be_false
      stderr.rewind.gets_to_end.should be_empty
    end

    it "correctly indents MartenImportmap::App when inserted into a non-empty installed_apps array" do
      settings_content = %(Marten.configure do |config|\n  config.installed_apps = [\n    Auth::App,\n    Groceries::App,\n  ] of Marten::Apps::Config.class\nend\n)

      MartenImportmap::CLI::Manage::Command::ImportmapSpec::TestImportmapCommand.prepare_project!(
        settings_content: settings_content
      )

      stdout = IO::Memory.new
      stderr = IO::Memory.new

      command = MartenImportmap::CLI::Manage::Command::ImportmapSpec::TestImportmapCommand.new(
        options: ["init"],
        stdout: stdout,
        stderr: stderr
      )

      command.handle

      content = File.read(MartenImportmap::CLI::Manage::Command::ImportmapSpec::TestImportmapCommand.settings_file_path)
      content.includes?("MartenImportmap::App").should be_true
      content.includes?("Auth::App").should be_true
      content.includes?("Groceries::App").should be_true
      content.includes?("\n  config.installed_apps = [").should be_true
      content.includes?("\n    config.installed_apps = [").should be_false
      stderr.rewind.gets_to_end.should be_empty
    end

    it "rejects resolver specifiers that escape the vendor directory" do
      stdout = IO::Memory.new
      stderr = IO::Memory.new

      init_command = MartenImportmap::CLI::Manage::Command::ImportmapSpec::TestImportmapCommand.new(
        options: ["init"],
        stdout: stdout,
        stderr: stderr
      )
      init_command.handle

      response = MartenImportmap::Resolver::GenerateResponse.from_json(
        %({"map":{"imports":{"../escape":"https://cdn.example/escape.js"}}})
      )
      MartenImportmap::CLI::Manage::Command::ImportmapSpec::TestImportmapCommand.response = response

      command = MartenImportmap::CLI::Manage::Command::ImportmapSpec::TestImportmapCommand.new(
        options: ["pin", "escape"],
        stdout: stdout,
        stderr: stderr,
        exit_raises: true
      )

      error = expect_raises(Marten::CLI::Manage::Errors::Exit) do
        command.handle!
      end

      error.code.should eq 1
      stderr.rewind.gets_to_end.includes?("Invalid import specifier '../escape' returned by resolver").should be_true
    end
  end
end
