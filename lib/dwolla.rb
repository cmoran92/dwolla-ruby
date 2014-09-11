# Dwolla Ruby API Wrapper
# Heavily based off Stripe's Ruby Gem
# API spec at https://developers.dwolla.com
require 'openssl'
require 'rest_client'
require 'multi_json'
require 'addressable/uri'

# Version
require_relative 'dwolla/version'

# Resources
require_relative 'dwolla/json'
require_relative 'dwolla/transactions'
require_relative 'dwolla/requests'
require_relative 'dwolla/contacts'
require_relative 'dwolla/users'
require_relative 'dwolla/balance'
require_relative 'dwolla/funding_sources'
require_relative 'dwolla/oauth'
require_relative 'dwolla/offsite_gateway'
require_relative 'dwolla/accounts'

# Errors
require_relative 'dwolla/errors/dwolla_error'
require_relative 'dwolla/errors/api_connection_error'
require_relative 'dwolla/errors/api_error'
require_relative 'dwolla/errors/missing_parameter_error'
require_relative 'dwolla/errors/authentication_error'
require_relative 'dwolla/errors/invalid_request_error'

module Dwolla
    @@api_key = nil
    @@api_secret = nil
    @@token = nil
    @@api_base = '/oauth/rest'
    @@verify_ssl_certs = true
    @@api_version = nil
    @@debug = false
    @@sandbox = false
    @@scope = 'send|transactions|balance|request|contacts|accountinfofull|funding'

    def self.api_key=(api_key)
        @@api_key = api_key
    end

    def self.api_key
        @@api_key
    end

    def self.api_secret=(api_secret)
        @@api_secret = api_secret
    end

    def self.api_secret
        @@api_secret
    end

    def self.sandbox=(sandbox)
        @@sandbox = sandbox
    end

    def self.sandbox
        @@sandbox
    end

    def self.debug
        @@debug
    end

    def self.debug=(debug)
        @@debug = debug
    end

    def self.api_version=(api_version)
        @@api_version = api_version
    end

    def self.api_version
        @@api_version
    end

    def self.verify_ssl_certs=(verify_ssl_certs)
        @@verify_ssl_certs = verify_ssl_certs
    end

    def self.verify_ssl_certs
        @@verify_ssl_certs
    end

    def self.token=(token)
        @@token = token
    end

    def self.token
        @@token
    end

    def self.scope=(scope)
        @@scope = scope
    end

    def self.scope
        @@scope
    end

    def self.hostname
        if not @@sandbox
            return 'https://www.dwolla.com'
        else
            return 'https://uat.dwolla.com'
        end
    end

    def self.endpoint_url(endpoint)
        self.hostname + @@api_base + endpoint
    end

    def self.request(method, url, params={}, headers={}, oauth=true, parse_response=true, custom_url=false)
        # if oauth is nil, assume default [true]
        oauth = true if oauth.nil?

        # figure out which auth to use
        if oauth and not params[:oauth_token]
            if not oauth.is_a?(TrueClass) # was token passed in the oauth param?
                params = {
                    :oauth_token => oauth
                }.merge(params)
            else
                raise AuthenticationError.new('No OAuth Token Provided.') unless token
                params = {
                    :oauth_token => token
                }.merge(params)
            end
        elsif oauth and params[:oauth_token]
            raise AuthenticationError.new('No OAuth Token Provided.') unless params[:oauth_token]
        else not oauth
            raise AuthenticationError.new('No App Key & Secret Provided.') unless (api_key && api_secret)
            params = {
                :client_id => api_key,
                :client_secret => api_secret
            }.merge(params)
        end

        if !verify_ssl_certs
            $stderr.puts "WARNING: Running without SSL cert verification."
        else
            ssl_opts = {
                :use_ssl => true
            }
        end

        uname = (@@uname ||= RUBY_PLATFORM =~ /linux|darwin/i ? `uname -a 2>/dev/null`.strip : nil)
        lang_version = "#{RUBY_VERSION} p#{RUBY_PATCHLEVEL} (#{RUBY_RELEASE_DATE})"
        ua = {
            :bindings_version => Dwolla::VERSION,
            :lang => 'ruby',
            :lang_version => lang_version,
            :platform => RUBY_PLATFORM,
            :publisher => 'dwolla',
            :uname => uname
        }

        url = self.endpoint_url(url) unless custom_url

        case method.to_s.downcase.to_sym
            when :get
                # Make params into GET parameters
                if params && params.count > 0
                    uri = Addressable::URI.new
                    uri.query_values = params
                    url += '?' + uri.query
                end
                payload = nil
            else
                payload = JSON.dump(params)
        end

        begin
            headers = { :x_dwolla_client_user_agent => Dwolla::JSON.dump(ua) }.merge(headers)
        rescue => e
            headers = {
                :x_dwolla_client_raw_user_agent => ua.inspect,
                :error => "#{e} (#{e.class})"
            }.merge(headers)
        end

        headers = {
            :user_agent => "Dwolla Ruby API Wrapper/#{Dwolla::VERSION}",
            :content_type => 'application/json'
        }.merge(headers)

        if self.api_version
            headers[:dwolla_version] = self.api_version
        end

        opts = {
            :method => method,
            :url => url,
            :headers => headers,
            :open_timeout => 30,
            :payload => payload,
            :timeout => 80
        }.merge(ssl_opts)

        if self.debug
            if self.sandbox
                puts "[DWOLLA SANDBOX MODE OPERATION]"
            end

            puts "Firing request with options and headers:"
            puts opts
            puts headers
        end

        begin
            response = execute_request(opts)
        rescue SocketError => e
            self.handle_restclient_error(e)
        rescue NoMethodError => e
            # Work around RestClient bug
            if e.message =~ /\WRequestFailed\W/
                e = APIConnectionError.new('Unexpected HTTP response code')
                self.handle_restclient_error(e)
            else
                raise
            end
        rescue RestClient::ExceptionWithResponse => e
            if rcode = e.http_code and rbody = e.http_body
                self.handle_api_error(rcode, rbody)
            else
                self.handle_restclient_error(e)
            end
        rescue RestClient::Exception, Errno::ECONNREFUSED => e
            self.handle_restclient_error(e)
        end

        rbody = response.body
        rcode = response.code

        if self.debug
            puts "Raw response headers received:"
            puts headers
            puts "Raw response body received:"
            puts rbody
        end

        resp = self.extract_json(rbody, rcode)

        if parse_response
            return self.parse_response(resp)
        else
            return resp
        end
    end

    private

    def self.execute_request(opts)
        RestClient::Request.execute(opts)
    end

    def self.extract_json(rbody, rcode)
        begin
            resp = Dwolla::JSON.load(rbody)
        rescue MultiJson::DecodeError
            raise APIError.new("There was an error parsing Dwolla's API response: #{rbody.inspect} (HTTP response code was #{rcode})", rcode, rbody)
        end

        return resp
    end

    def self.parse_response(resp)
        raise APIError.new(resp['Message']) unless resp['Success']

        return resp['Response']
    end

    def self.handle_api_error(rcode, rbody)
        begin
            error_obj = Dwolla::JSON.load(rbody)
            error = error_obj[:error] or raise DwollaError.new # escape from parsing
        rescue MultiJson::DecodeError, DwollaError
            raise APIError.new("Invalid response object from API: #{rbody.inspect} (HTTP response code was #{rcode})", rcode, rbody)
        end

        case rcode
            when 400, 404 then
                raise invalid_request_error(error, rcode, rbody, error_obj)
            when 401
                raise authentication_error(error, rcode, rbody, error_obj)
            else
                raise api_error(error, rcode, rbody, error_obj)
        end
    end

    def self.invalid_request_error(error, rcode, rbody, error_obj)
        InvalidRequestError.new(error[:message], error[:param], rcode, rbody, error_obj)
    end

    def self.authentication_error(error, rcode, rbody, error_obj)
        AuthenticationError.new(error[:message], rcode, rbody, error_obj)
    end

    def self.api_error(error, rcode, rbody, error_obj)
        APIError.new(error[:message], rcode, rbody, error_obj)
    end

    def self.handle_restclient_error(e)
        case e
            when RestClient::ServerBrokeConnection, RestClient::RequestTimeout
                message = "Could not connect to Dwolla (#{@@api_base}).  Please check your internet connection and try again.  If this problem persists, you should check Dwolla's service status at https://twitter.com/Dwolla, or let us know at support@Dwolla.com."
            when RestClient::SSLCertificateNotVerified
                message = "Could not verify Dwolla's SSL certificate. If this problem persists, let us know at support@dwolla.com."
            when SocketError
                message = "Unexpected error communicating when trying to connect to Dwolla. If this problem persists, let us know at support@dwolla.com."
            else
                message = "Unexpected error communicating with Dwolla. If this problem persists, let us know at support@dwolla.com."
        end

        message += "\n\n(Network error: #{e.message})"

        raise APIConnectionError.new(message)
    end
end
