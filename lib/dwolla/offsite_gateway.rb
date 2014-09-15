module Dwolla
    class OffsiteGateway
        @products = []
        @discount = 0
        @tax = 0
        @shipping = 0
        @notes = nil
        @facilitator_amount = nil
        @test_mode = false
        @allow_funding_sources = true
        @additional_funding_sources = true
        @order_id = nil

        def self.clear_session
            @products = []
            @discount = 0
            @tax = 0
            @shipping = 0
            @notes = nil
            @facilitator_amount = nil
            @test_mode = false
            @allow_funding_sources = true
            @additional_funding_sources = true
            @order_id = nil
        end

        class << self
            attr_writer :tax
            attr_writer :shipping
            attr_writer :notes
            attr_writer :order_id
            attr_writer :redirect
            attr_writer :callback
            attr_writer :test_mode
            attr_writer :allow_funding_sources
            attr_writer :additional_funding_sources
            attr_writer :facilitator_amount
        end

        def self.add_product(name=nil, description=nil, price=nil, quantity=1)
            @products.push({
                :name => name,
                :description => description,
                :price => price,
                :quantity => quantity
            })
        end

        def self.set_customer_info(first_name=nil, last_name=nil, email=nil, city=nil, state=nil, zip=nil)
            @customerInfo = {
                :firstName => first_name,
                :lastName => last_name,
                :email => email,
                :city => city,
                :state => state,
                :zip => zip
            }
        end

        def self.discount=(discount)
            @discount = -(discount.abs)
        end

        def self.get_checkout_url(destinationId)
            params = {
                :key => Dwolla::api_key,
                :secret => Dwolla::api_secret,
                :allowFundingSources => @allow_funding_sources,
                :additionalFundingSources => @additional_funding_sources,
                :test => @test_mode,
                :callback => @callback,
                :redirect => @redirect,
                :orderId => @order_id,
                :notes => @notes,
                :purchaseOrder => {
                    :customerInfo => @customerInfo,
                    :destinationId => destinationId,
                    :orderItems => @products,
                    :facilitatorAmount => @facilitator_amount,
                    :discount => @discount,
                    :shipping => @shipping,
                    :tax => @tax,
                    :total => self.calculate_total
                }
            }

            resp = Dwolla.request(:post, request_url, params, {}, false, false, true)
            raise APIError.new(resp['Message']) unless resp['Result'] == 'Success'

            return checkout_url + resp['CheckoutId']
        end

        def self.read_callback(body)
            data = JSON.load(body)

            verify_callback_signature(data['Signature'], data['CheckoutId'], data['Amount'])

            return data
        end

        def self.validate_webhook(signature, body)
            verify_webhook_signature(signature, body)
        end

        private

        def self.verify_callback_signature(candidate=nil, checkout_id=nil, amount=nil)
            key = "#{checkout_id}&#{amount}"
            digest  = OpenSSL::Digest::Digest.new('sha1')
            signature = OpenSSL::HMAC.hexdigest(digest, Dwolla::api_secret, key)

            raise APIError.new("Invalid callback signature (#{candidate} vs #{signature})") unless candidate == signature
        end

        def self.verify_webhook_signature(candidate=nil, body=nil)
            digest  = OpenSSL::Digest::Digest.new('sha1')
            signature = OpenSSL::HMAC.hexdigest(digest, Dwolla::api_secret, body)

            raise APIError.new("Invalid Webhook signature (#{candidate} vs #{signature})") unless candidate == signature
        end

        def self.request_url
            if Dwolla::sandbox
                return 'https://uat.dwolla.com/payment/request'
            else
                return 'https://www.dwolla.com/payment/request'
            end
        end

        def self.checkout_url
            if Dwolla::sandbox
                return 'https://uat.dwolla.com/payment/checkout/'
            else
                return 'https://www.dwolla.com/payment/checkout/'
            end
        end

        def self.calculate_total
            total = 0.0

            @products.each { |product|
                total += product[:price] * product[:quantity]
            }

            total += @shipping
            total += @tax
            total += @discount

            return total.round(2)
        end
    end
end
