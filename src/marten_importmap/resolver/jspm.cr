require "http/client"
require "json"
require "uri"

module MartenImportmap
  module Resolver
    class Error < Exception; end

    enum Provider
      JspmIo
      Jsdelivr
      Unpkg
      Skypack
      EsmSh

      def to_jspm_default_provider : String
        case self
        when JspmIo   then "jspm.io"
        when Jsdelivr then "jsdelivr"
        when Unpkg    then "unpkg"
        when Skypack  then "skypack"
        when EsmSh    then "esm.sh"
        else
          raise "Unsupported provider: #{self}"
        end
      end

      def self.from_cli(value : String) : Provider?
        case value.downcase
        when "jspm.io", "jspm" then Provider::JspmIo
        when "jsdelivr"        then Provider::Jsdelivr
        when "unpkg"           then Provider::Unpkg
        when "skypack"         then Provider::Skypack
        when "esm.sh", "esmsh" then Provider::EsmSh
        else
          nil
        end
      end

      def self.valid_values : Array(String)
        ["jspm.io", "jsdelivr", "unpkg", "skypack", "esm.sh"]
      end
    end

    struct ImportMapPayload
      include JSON::Serializable

      property imports : Hash(String, String) = {} of String => String
      property scopes : Hash(String, Hash(String, String))? = nil
    end

    struct GenerateResponse
      include JSON::Serializable

      @[JSON::Field(key: "staticDeps")]
      property static_deps : Array(String) = [] of String

      @[JSON::Field(key: "dynamicDeps")]
      property dynamic_deps : Array(String) = [] of String

      @[JSON::Field(key: "map")]
      property map : ImportMapPayload? = nil

      property error : String? = nil

      def imports : Hash(String, String)
        map.try(&.imports) || {} of String => String
      end
    end

    module Jspm
      API = URI.parse("https://api.jspm.io/generate")
      DEFAULT_ENV = ["browser", "production", "module"]

      def self.generate(
        install : Array(String),
        env : Array(String) = DEFAULT_ENV,
        provider : Provider = Provider::JspmIo,
        flatten_scope : Bool = true,
        input_map : ImportMapPayload? = nil
      ) : GenerateResponse
        body = build_payload(
          install: install,
          env: env,
          provider: provider,
          flatten_scope: flatten_scope,
          input_map: input_map
        )

        headers = HTTP::Headers{
          "Content-Type" => "application/json",
          "Accept"       => "application/json",
          "User-Agent"   => "marten-importmap-resolver/0.1",
        }

        response_body = http_post(API, headers, body)
        parsed = GenerateResponse.from_json(response_body)

        if err = parsed.error
          raise Error.new("JSPM generator error: #{err}")
        end

        if parsed.map.nil?
          raise Error.new("JSPM generator returned no import map entries")
        end

        parsed
      rescue ex : JSON::ParseException
        raise Error.new("Unable to parse JSPM response: #{ex.message}")
      end

      def self.resolve_one(
        install_spec : String,
        env : Array(String) = DEFAULT_ENV,
        provider : Provider = Provider::JspmIo,
        flatten_scope : Bool = true,
        input_map : ImportMapPayload? = nil
      ) : GenerateResponse
        generate(
          install: [install_spec],
          env: env,
          provider: provider,
          flatten_scope: flatten_scope,
          input_map: input_map
        )
      end

      def self.pin_key_guess(install_spec : String) : String
        spec = install_spec

        if spec.starts_with?('@')
          slash = spec.index('/') || return spec
          ver_at = spec.index('@', slash + 1)
          return spec unless ver_at
        else
          ver_at = spec.index('@')
          return spec unless ver_at
        end

        slash_after_ver = spec.index('/', ver_at.not_nil! + 1)
        if slash_after_ver
          name = spec[0, ver_at.not_nil!]
          sub = spec[slash_after_ver..-1]
          "#{name}#{sub}"
        else
          spec[0, ver_at.not_nil!]
        end
      end

      private def self.build_payload(
        install : Array(String),
        env : Array(String),
        provider : Provider,
        flatten_scope : Bool,
        input_map : ImportMapPayload?
      ) : String
        String.build do |io|
          JSON.build(io) do |json|
            json.object do
              json.field "install" do
                json.array do
                  install.each { |item| json.string(item) }
                end
              end

              json.field "env" do
                json.array do
                  env.each { |item| json.string(item) }
                end
              end

              json.field "flattenScope", flatten_scope
              json.field "defaultProvider", provider.to_jspm_default_provider

              unless input_map.nil?
                json.field "inputMap" do
                  input_map.not_nil!.to_json(json)
                end
              end
            end
          end
        end
      end

      private def self.http_post(uri : URI, headers : HTTP::Headers, body : String) : String
        tls = uri.scheme == "https"
        port = uri.port || (tls ? 443 : 80)
        host = uri.host || raise Error.new("Invalid resolver URI '#{uri}'")

        client = HTTP::Client.new(host, port, tls: tls)
        client.connect_timeout = 5.seconds
        client.read_timeout = 20.seconds
        client.write_timeout = 20.seconds

        path = uri.path
        path = "/" if path.empty?
        path += "?#{uri.query}" unless uri.query.nil?

        response = client.post(path, headers: headers, body: body)

        unless response.status.success?
          snippet = response.body[0, Math.min(500, response.body.bytesize)]
          raise Error.new("HTTP #{response.status_code} from #{uri}: #{snippet}")
        end

        response.body
      rescue ex : IO::Error
        raise Error.new("Failed to call JSPM API: #{ex.message}")
      ensure
        client.try(&.close)
      end
    end
  end
end
