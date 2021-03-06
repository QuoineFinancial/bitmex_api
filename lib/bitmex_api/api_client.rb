require 'date'
require 'json'
require 'logger'
require 'tempfile'
require 'typhoeus'
require 'uri'
require 'openssl'

module BitmexApi
  class ApiClient

    attr_accessor :host

    # Defines the headers to be used in HTTP requests of all API calls by default.
    #
    # @return [Hash]
    attr_accessor :default_headers

    # Stores the HTTP response from the last API call using this API client.
    attr_accessor :last_response
    attr_accessor :access_token

    def initialize(host = nil, access_token = nil)
      @host = host || Configuration.base_url
      @format = 'json'
      @user_agent = "ruby-swagger-#{VERSION}"
      @default_headers = {
        'Content-Type' => "application/#{@format.downcase}",
        'User-Agent' => @user_agent
      }
      @access_token = access_token
    end

    def call_api(http_method, path, opts = {})
      request = build_request(http_method, path, opts)
      response = request.run

      # record as last response
      @last_response = response

      if Configuration.debugging
        Configuration.logger.debug "HTTP response body ~BEGIN~\n#{response.body}\n~END~\n"
      end

      unless response.success?
        fail ApiError.new(:code => response.code,
                          :response_headers => response.headers,
                          :response_body => response.body),
             response.status_message
      end

      if opts[:return_type]
        deserialize(response, opts[:return_type])
      else
        nil
      end
    end

    def build_auth_header(http_method, path, query, data)
      if @access_token
        return { "AccessToken" => @access_token }
      end
      http_method = http_method.to_s.upcase
      nonce = (Time.now.to_f * 1000).to_i
      query_string = "?" + URI.encode_www_form(query)
      path = path + query_string if query_string.length > 1

      request_path = (Configuration.base_path + path).gsub(/\/+/, '/')

      signature = OpenSSL::HMAC.hexdigest(
        OpenSSL::Digest.new('sha256'),
        Configuration.api_secret,
        http_method + request_path + nonce.to_s + data
      )

      if Configuration.debugging
        data_log = {
          nonce: nonce,
          http_method: http_method,
          request_path: request_path,
          data: data,
          signed: http_method + request_path + nonce.to_s + data,
          api_key: Configuration.api_key,
          api_secret: Configuration.api_secret
        }

        Configuration.logger.debug "[AuthHeader]#{data_log}"
      end

      {
        "api-nonce" => nonce,
        "api-key" => Configuration.api_key,
        "api-signature" => signature
      }
    end

    def build_request(http_method, path, opts = {})
      url = build_request_url(path)
      http_method = http_method.to_sym.downcase

      header_params = @default_headers.merge(opts[:header_params] || {})
      query_params = opts[:query_params] || {}
      form_params = opts[:form_params] || {}

      req_opts = {
        :method => http_method,
        :headers => header_params,
        :params => query_params,
        :ssl_verifypeer => Configuration.verify_ssl,
        :sslcert => Configuration.cert_file,
        :sslkey => Configuration.key_file,
        :cainfo => Configuration.ssl_ca_cert,
        :verbose => Configuration.debugging
      }

      body = ''
      if [:post, :patch, :put, :delete].include?(http_method)
        header_params['Content-Type'] = 'application/x-www-form-urlencoded'

        req_body = build_request_body(header_params, form_params, opts[:body])
        body = req_body ? URI.encode_www_form(req_body) : ''
        req_opts.update :body => body
        if Configuration.debugging
          Configuration.logger.debug "HTTP request body param ~BEGIN~\n#{body}\n~END~\n"
        end
      end
      req_opts[:headers].merge!(build_auth_header(http_method, path, query_params, body))
      if Configuration.debugging
        Configuration.logger.debug "HTTP request header params ~BEGIN~\n#{req_opts[:headers]}\n~END~\n"
      end

      Typhoeus::Request.new(url, req_opts)
    end

    # Deserialize the response to the given return type.
    #
    # @param [String] return_type some examples: "User", "Array[User]", "Hash[String,Integer]"
    def deserialize(response, return_type)
      body = response.body
      return nil if body.nil? || body.empty?

      # handle file downloading - save response body into a tmp file and return the File instance
      return download_file(response) if return_type == 'File'

      # ensuring a default content type
      content_type = response.headers['Content-Type'] || 'application/json'

      unless content_type.start_with?('application/json')
        fail "Content-Type is not supported: #{content_type}"
      end

      begin
        data = JSON.parse("[#{body}]", :symbolize_names => true)[0]
      rescue JSON::ParserError => e
        if %w(String Date DateTime).include?(return_type)
          data = body
        else
          raise e
        end
      end

      convert_to_type data, return_type
    end

    # Convert data to the given return type.
    def convert_to_type(data, return_type)
      return nil if data.nil?
      case return_type
      when 'String'
        data.to_s
      when 'Integer'
        data.to_i
      when 'Float'
        data.to_f
      when 'BOOLEAN'
        data == true
      when 'DateTime'
        # parse date time (expecting ISO 8601 format)
        DateTime.parse data
      when 'Date'
        # parse date time (expecting ISO 8601 format)
        Date.parse data
      when 'Object'
        # generic object, return directly
        data
      when /\AArray<(.+)>\z/
        # e.g. Array<Pet>
        sub_type = $1
        data.map {|item| convert_to_type(item, sub_type) }
      when /\AHash\<String, (.+)\>\z/
        # e.g. Hash<String, Integer>
        sub_type = $1
        {}.tap do |hash|
          data.each {|k, v| hash[k] = convert_to_type(v, sub_type) }
        end
      else
        # models, e.g. Pet
        BitmexApi.const_get(return_type).new.tap do |model|
          model.build_from_hash data
        end
      end
    end

    # Save response body into a file in (the defined) temporary folder, using the filename
    # from the "Content-Disposition" header if provided, otherwise a random filename.
    #
    # @see Configuration#temp_folder_path
    # @return [File] the file downloaded
    def download_file(response)
      tmp_file = Tempfile.new '', Configuration.temp_folder_path
      content_disposition = response.headers['Content-Disposition']
      if content_disposition
        filename = content_disposition[/filename=['"]?([^'"\s]+)['"]?/, 1]
        path = File.join File.dirname(tmp_file), filename
      else
        path = tmp_file.path
      end
      # close and delete temp file
      tmp_file.close!

      File.open(path, 'w') { |file| file.write(response.body) }
      Configuration.logger.info "File written to #{path}. Please move the file to a proper "\
                                "folder for further processing and delete the temp afterwards"
      File.new(path)
    end

    def build_request_url(path)
      # Add leading and trailing slashes to path
      path = "/#{path}".gsub(/\/+/, '/')
      URI.encode(host + path)
    end

    def build_request_body(header_params, form_params, body)
      # http form
      if header_params['Content-Type'] == 'application/x-www-form-urlencoded' ||
          header_params['Content-Type'] == 'multipart/form-data'
        data = form_params.dup
        data.each do |key, value|
          data[key] = value.to_s if value && !value.is_a?(File)
        end
      elsif body
        data = body.is_a?(String) ? body : body.to_json
      else
        data = nil
      end
      data
    end

    # Update hearder and query params based on authentication settings.
    def update_params_for_auth!(header_params, query_params, auth_names)
      Array(auth_names).each do |auth_name|
        auth_setting = Configuration.auth_settings[auth_name]
        next unless auth_setting
        case auth_setting[:in]
        when 'header' then header_params[auth_setting[:key]] = auth_setting[:value]
        when 'query'  then query_params[auth_setting[:key]] = auth_setting[:value]
        else fail ArgumentError, 'Authentication token must be in `query` of `header`'
        end
      end
    end

    def user_agent=(user_agent)
      @user_agent = user_agent
      @default_headers['User-Agent'] = @user_agent
    end

    # Return Accept header based on an array of accepts provided.
    # @param [Array] accepts array for Accept
    # @return [String] the Accept header (e.g. application/json)
    def select_header_accept(accepts)
      if accepts.empty?
        return
      elsif accepts.any?{ |s| s.casecmp('application/json') == 0 }
        'application/json' # look for json data by default
      else
        accepts.join(',')
      end
    end

    # Return Content-Type header based on an array of content types provided.
    # @param [Array] content_types array for Content-Type
    # @return [String] the Content-Type header  (e.g. application/json)
    def select_header_content_type(content_types)
      if content_types.empty?
        'application/json' # use application/json by default
      elsif content_types.any?{ |s| s.casecmp('application/json')==0 }
        'application/json' # use application/json if it's included
      else
        content_types[0] # otherwise, use the first one
      end
    end

    # Convert object (array, hash, object, etc) to JSON string.
    # @param [Object] model object to be converted into JSON string
    # @return [String] JSON string representation of the object
    def object_to_http_body(model)
      return if model.nil?
      _body = nil
      if model.is_a?(Array)
        _body = model.map{|m| object_to_hash(m) }
      else
        _body = object_to_hash(model)
      end
      _body.to_json
    end

    # Convert object(non-array) to hash.
    # @param [Object] obj object to be converted into JSON string
    # @return [String] JSON string representation of the object
    def object_to_hash(obj)
      if obj.respond_to?(:to_hash)
        obj.to_hash
      else
        obj
      end
    end
  end
end
