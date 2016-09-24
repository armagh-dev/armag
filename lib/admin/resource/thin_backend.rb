require 'thin'
module Armagh
  module Admin
    module Resource
    
      class ThinBackend < ::Thin::Backends::TcpServer

        def initialize( host, port, options )
          super( host, port )
          api = Armagh::Admin::Resource::API.instance
          if api.using_ssl?
            @ssl         = true
            @ssl_options = options
          end
        end

      end
    end
  end 
end 