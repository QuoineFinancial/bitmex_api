module BitmexApi
  # 
  class Error < BaseObject
    attr_accessor :message, :code
    # attribute mapping from ruby-style variable name to JSON key
    def self.attribute_map
      {
        
        # 
        :'message' => :'message',
        
        # 
        :'code' => :'code'
        
      }
    end

    # attribute type
    def self.swagger_types
      {
        :'message' => :'String',
        :'code' => :'Float'
        
      }
    end

    def initialize(attributes = {})
      return if !attributes.is_a?(Hash) || attributes.empty?

      # convert string to symbol for hash key
      attributes = attributes.inject({}){|memo,(k,v)| memo[k.to_sym] = v; memo}

      
      if attributes[:'message']
        self.message = attributes[:'message']
      end
      
      if attributes[:'code']
        self.code = attributes[:'code']
      end
      
    end

  end
end
