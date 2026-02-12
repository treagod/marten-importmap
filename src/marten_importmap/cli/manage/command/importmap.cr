require "http/client"
require "marten/cli"
require "set"
require "uri"

module MartenImportmap
  module CLI
    class Manage
      module Command
        class Importmap < Marten::CLI::Manage::Command::Base
          command_name :importmap
          help "Manage JavaScript import map entries."

          @subcommand : String?
          @library : String?
          @provider_name : String?

          def setup
            on_argument(:subcommand, "Subcommand to execute (currently: pin)") do |value|
              @subcommand = value
            end

            on_argument(:library, "Name of the JavaScript library to pin") do |value|
              @library = value
            end

            on_option_with_arg(
              :from,
              arg: "provider",
              description: "Specify the package provider (for example: jsdelivr)"
            ) do |value|
              @provider_name = value
            end
          end

          def run
            if subcommand.nil?
              print_error_and_exit("Please provide an importmap subcommand (for example: pin)")
            end

            case subcommand
            when "pin"
              run_pin
            else
              print_error_and_exit("Unsupported importmap subcommand '#{subcommand}'")
            end
          end

          protected def resolve_library(library : String, provider : MartenImportmap::Resolver::Provider)
            MartenImportmap::Resolver::Jspm.resolve_one(library, provider: provider)
          end

          protected def download_file(url : String, target_path : String)
            uri = URI.parse(url)

            tls = uri.scheme == "https"
            port = uri.port || (tls ? 443 : 80)
            host = uri.host || raise MartenImportmap::Resolver::Error.new("Invalid module URL '#{url}'")

            client = HTTP::Client.new(host, port, tls: tls)
            client.connect_timeout = 5.seconds
            client.read_timeout = 30.seconds
            client.write_timeout = 20.seconds

            path = uri.path
            path = "/" if path.empty?
            path += "?#{uri.query}" unless uri.query.nil?

            response = client.get(path)

            unless response.status.success?
              snippet = response.body[0, Math.min(500, response.body.bytesize)]
              raise MartenImportmap::Resolver::Error.new("HTTP #{response.status_code} while downloading #{url}: #{snippet}")
            end

            Dir.mkdir_p(File.dirname(target_path))
            File.write(target_path, response.body)
          rescue ex : IO::Error
            raise MartenImportmap::Resolver::Error.new("Failed to download #{url}: #{ex.message}")
          ensure
            client.try(&.close)
          end

          private def run_pin
            if library.nil?
              print_error_and_exit("Please provide a JavaScript library to pin")
            end

            provider = resolved_provider
            response = resolve_library(library.not_nil!, provider)
            imports = response.imports

            if imports.empty?
              print_error_and_exit("No import map entries were returned for '#{library}'")
            end

            pin_entries = if keep_cdn_urls?
                            imports
                          else
                            vendorize_imports(imports)
                          end

            print_pin_snippet(pin_entries)
          rescue ex : MartenImportmap::Resolver::Error
            print_error_and_exit(ex.message || "Unable to pin '#{library}'")
          end

          private def keep_cdn_urls? : Bool
            importmap_settings.keep_cdn_urls? || false
          end

          private def resolved_provider : MartenImportmap::Resolver::Provider
            return MartenImportmap::Resolver::Provider::JspmIo if provider_name.nil?

            provider = MartenImportmap::Resolver::Provider.from_cli(provider_name.not_nil!)
            return provider unless provider.nil?

            supported = MartenImportmap::Resolver::Provider.valid_values.join(", ")
            print_error_and_exit("Unsupported provider '#{provider_name}'. Supported providers: #{supported}")

            MartenImportmap::Resolver::Provider::JspmIo
          end

          private def vendorize_imports(imports : Hash(String, String)) : Hash(String, String)
            vendor_dir = Path.new(importmap_settings.vendor_scripts_dir).expand.to_s
            used_paths = Set(String).new
            output = {} of String => String

            imports.keys.sort.each do |specifier|
              url = imports[specifier]
              target_path = next_vendor_target(vendor_dir, specifier, url, used_paths)

              download_file(url, target_path)

              used_paths << target_path
              output[specifier] = asset_relative_path(target_path)
            end

            output
          end

          private def next_vendor_target(
            vendor_dir : String,
            specifier : String,
            url : String,
            used_paths : Set(String)
          ) : String
            relative = normalized_vendor_relative_path(specifier, url)
            path = Path.new(vendor_dir).join(relative).normalize.to_s

            return path unless used_paths.includes?(path) || File.exists?(path)

            ext = File.extname(path)
            stem = path.sub(/#{Regex.escape(ext)}\z/, "")
            idx = 2

            loop do
              candidate = "#{stem}-#{idx}#{ext}"
              return candidate unless used_paths.includes?(candidate) || File.exists?(candidate)
              idx += 1
            end
          end

          private def normalized_vendor_relative_path(specifier : String, url : String) : String
            path = specifier.strip
            path = path.sub(/\A@/, "")
            path = path.gsub(/[^a-zA-Z0-9\-\._\/]/, "_")
            path = path.gsub(/\/+/, "/")
            path = path.sub(/\A\//, "")
            path = path.sub(/\/\z/, "")
            path = "module" if path.empty?

            unless path.ends_with?(".js") || path.ends_with?(".mjs") || path.ends_with?(".cjs")
              path += inferred_extension(url)
            end

            path
          end

          private def inferred_extension(url : String) : String
            uri = URI.parse(url)
            ext = File.extname(uri.path).downcase

            case ext
            when ".js", ".mjs", ".cjs"
              ext
            else
              ".js"
            end
          rescue URI::Error
            ".js"
          end

          private def asset_relative_path(target_path : String) : String
            assets_root = Path.new("src/assets").expand.to_s
            root_prefix = assets_root.ends_with?("/") ? assets_root : "#{assets_root}/"
            expanded_target = Path.new(target_path).expand.to_s

            unless expanded_target.starts_with?(root_prefix)
              raise MartenImportmap::Resolver::Error.new(
                "Configured vendor_scripts_dir must be inside src/assets (current value: #{importmap_settings.vendor_scripts_dir})"
              )
            end

            expanded_target[root_prefix.size..-1]
          end

          private def importmap_settings : MartenImportmap::Configuration
            Marten.settings.importmap.as(MartenImportmap::Configuration)
          end

          private def print_pin_snippet(entries : Hash(String, String))
            print("config.importmap.draw do")

            entries.keys.sort.each do |specifier|
              path = entries[specifier]
              print(%(  pin "#{escaped(specifier)}", "#{escaped(path)}"))
            end

            print("end")
          end

          private def escaped(value : String) : String
            value.gsub("\\", "\\\\").gsub("\"", "\\\"")
          end

          private getter subcommand
          private getter library
          private getter provider_name
        end
      end
    end
  end
end
