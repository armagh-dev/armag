# Copyright 2017 Noragh Analytics, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either
# express or implied.
#
# See the License for the specific language governing permissions and
# limitations under the License.
#

require 'json'

require_relative '../logging'

module Armagh
  module Utils
    class RestHelper
      def initialize(logger, realm)
        @logger = logger
        @realm = realm
      end

      def headers=(headers)
        @headers = headers
      end

      def handle_request(request, role = nil, allowed_userid = nil)
        begin
          remote_user = authenticate_request(request, role, allowed_userid)
          params = parse_request(request)
          successful_result = yield params, remote_user
          respond_success( successful_result )
        rescue Armagh::Authentication::AuthenticationError => e
          respond_authentication_exception(request, e)
        rescue Admin::Application::APIClientError => e
          respond_client_exception(request, e)
        rescue => e
          respond_server_exception( request, e )
        end
      end

      def authenticate_request(request, role, allowed_userid)
        auth = Rack::Auth::Basic::Request.new(request.env)
        if auth.provided? and auth.basic?
          username, password = auth.credentials
          user = Authentication::User.authenticate(username, password)
          if (role.nil? && allowed_userid.nil?) || (role && user.has_role?(role)) || (allowed_userid && user.internal_id.to_s == allowed_userid.to_s)
            user
          else
            if role
              message = "User #{username} does not have the required role of #{role.name}."
            else
              message = "User #{username} does not have the required permission."
            end
            raise Authentication::AuthenticationError, message
          end
        else
          @headers['WWW-Authenticate'] = "Basic realm=\"#{@realm}\"" if @headers
          raise Authentication::AuthenticationError, 'Authentication required.'
        end
      end

      def parse_request(request)
        body = request.body.string
        body = "(#{body}}" unless body.empty?
        @logger.debug "Handling request: #{request.request_method} #{request.url} #{body}"
        body = (request.post? || request.put? || request.patch?) ? request.body.read : Rack::Utils.unescape(request.query_string)

        begin
          request_hash = JSON.parse(body) unless body.nil? || body.empty?
        rescue JSON::ParserError; end

        request_hash ||= request.params unless request.params.empty?
        request_hash ||= {}

        respond_client_error( 'Request body must be a hash') unless request_hash.is_a?( Hash )
        request_hash
      rescue => e
        respond_server_exception( request, e )
      end

      def respond_server_exception(request, exception)
        Logging.dev_error_exception(@logger, exception, "Server Error: #{request.inspect}")
        [500, JSON.pretty_generate({'server_error_detail' => {'class' => exception.class, 'message' => exception.message}})]
      end

      def respond_server_error(request, message)
        @logger.dev_error "Server error: #{message} when handling request #{request.inspect}"
        [500, JSON.pretty_generate({'server_error_detail' => {'message' => message}})]
      end

      def respond_success(value)
        @logger.debug "Successful request.  Responding with: #{value}"
        [200, JSON.pretty_generate( value ) ]
      end

      def respond_client_exception(request, exception)
        @logger.debug Logging::EnhancedException.new("Client Error: #{request.inspect}", exception)
        [400, JSON.pretty_generate( { 'client_error_detail' => { 'message' => exception.message, 'markup' => exception.markup }})]
      end

      def respond_client_error(request, message = 'Unspecified error in request', markup = nil )
        @logger.debug "Client error in request #{request}.  Responding with: #{message}: #{markup}"
        [400, JSON.pretty_generate( { 'client_error_detail' => { 'message' => message, 'markup' => markup }})]
      end

      def respond_authentication_exception(request, exception)
        @logger.debug Logging::EnhancedException.new("Authentication error: #{request.inspect}",  exception)
        [401, JSON.pretty_generate({'authentication_error_detail' => {'message' => exception.message}})]
      end
    end
  end
end
