require 'thin'

module Armagh
  module Admin
    module Application
    
      class ThinBackend < ::Thin::Backends::TcpServer

        def initialize( host, port, options )
          super( host, port )
          api = Armagh::Admin::Application::API.instance
          if api.using_ssl?
            @ssl         = true
            @ssl_options = options
          end
        end
      end
    end
  end
end 