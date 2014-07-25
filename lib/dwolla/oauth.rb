module Dwolla
    class OAuth
        def self.get_auth_url(redirect_uri=nil, scope=Dwolla::scope)
            raise AuthenticationError.new('No Api Key Provided.') unless Dwolla::api_key

            params = {
                :scope => scope,
                :response_type => 'code',
                :client_id => Dwolla::api_key
            }

            params['redirect_uri'] = redirect_uri unless redirect_uri.nil?

            uri = Addressable::URI.new
            uri.query_values = params

            if Dwolla::debug and Dwolla::sandbox
                puts "[DWOLLA SANDBOX MODE OPERATION]"
            end

            return auth_url + '?' + uri.query
        end

        def self.get_token(code=nil, redirect_uri=nil)
            raise MissingParameterError.new('No Code Provided.') if code.nil?

            params = {
                :grant_type => 'authorization_code',
                :code => code
            }

            params['redirect_uri'] = redirect_uri unless redirect_uri.nil?

            resp = Dwolla.request(:get, token_url, params, {}, false, false, true)

            raise APIError.new(resp['error_description']) unless resp['access_token'] and resp['refresh_token']

            return resp
        end

        def self.refresh_auth(refresh_token=nil, redirect_uri=nil)
          raise MissingParameterError.new('No Refresh Token Provided') if refresh_token.nil?

          params = {
              :grant_type => 'refresh_token',
              :refresh_token => refresh_token
          }

          params['redirect_uri'] = redirect_uri unless redirect_uri.nil?

          resp = Dwolla.request(:get, token_url, params, {}, false, false, true)

          raise APIError.new(resp['error_description']) unless resp['access_token'] and resp['refresh_token']

          return resp
        end

        private

        def self.auth_url
            Dwolla.hostname + '/oauth/v2/authenticate'
        end

        def self.token_url
            Dwolla.hostname + '/oauth/v2/token'
        end
    end
end
