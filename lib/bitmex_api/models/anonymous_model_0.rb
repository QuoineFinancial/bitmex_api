module BitmexApi
  # 
  class AnonymousModel0 < BaseObject
    attr_accessor :apns, :gcm
    # attribute mapping from ruby-style variable name to JSON key
    def self.attribute_map
      {
        
        # 
        :'apns' => :'apns',
        
        # 
        :'gcm' => :'gcm'
        
      }
    end

    # attribute type
    def self.swagger_types
      {
        :'apns' => :'x-any',
        :'gcm' => :'x-any'
        
      }
    end

    def initialize(attributes = {})
      return if !attributes.is_a?(Hash) || attributes.empty?

      # convert string to symbol for hash key
      attributes = attributes.inject({}){|memo,(k,v)| memo[k.to_sym] = v; memo}

      
      if attributes[:'apns']
        self.apns = attributes[:'apns']
      end
      
      if attributes[:'gcm']
        self.gcm = attributes[:'gcm']
      end
      
    end

  end
end
