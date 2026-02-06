module MartenImportmap
  module Template
    module Tag
      class ImportMapTag < Marten::Template::Tag::Base
        include Marten::Template::Tag::CanSplitSmartly

        @namespace_expr : Marten::Template::FilterExpression?
        @entrypoint_expr : Marten::Template::FilterExpression?

        def initialize(parser : Marten::Template::Parser, source : String)
          parts = split_smartly(source)
          args = parts[1..]

          @namespace_expr = nil
          @entrypoint_expr = nil

          if args.size >= 1
            @namespace_expr = Marten::Template::FilterExpression.new(args[0])
          end

          if args.size >= 2
            if m = args[1].match(/\Aentrypoint[:=](.+)\z/)
              @entrypoint_expr = Marten::Template::FilterExpression.new(m[1])
            else
              raise Marten::Template::Errors::InvalidSyntax.new(
                "Malformed importmap tag: second argument must be entrypoint:<value>"
              )
            end
          end

          if args.size > 2
            raise Marten::Template::Errors::InvalidSyntax.new(
              "Malformed importmap tag: expected {% importmap %}, {% importmap <namespace> %}, or {% importmap <namespace> entrypoint:<value> %}"
            )
          end
        end

        def render(context : Marten::Template::Context) : String
          ns = @namespace_expr.try(&.resolve(context)).try(&.to_s)
          ep = @entrypoint_expr.try(&.resolve(context)).try(&.to_s)

          if ns.nil? || ns.empty?
            ImportMap.tag(entrypoint: "application")
          elsif ep.nil? || ep.empty?
            ImportMap.tag(ns, entrypoint: "application")
          else
            ImportMap.tag(ns, entrypoint: ep)
          end
        end
      end
    end
  end
end
