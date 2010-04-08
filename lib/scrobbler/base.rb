require 'digest/md5'

$KCODE = 'u'

include LibXML

module Scrobbler
  
  API_URL     = 'http://ws.audioscrobbler.com/'
  
class Base
    def Base.api_key=(api_key) 
        @@api_key = api_key
    end

    def Base.secret=(secret)
        @@secret = secret
    end

    def Base.connection
        @connection ||= REST::Connection.new(API_URL)
    end
    
    def Base.sanitize(param)
      URI.escape(param.to_s, Regexp.new("[^#{URI::PATTERN::UNRESERVED}]"))
    end

    # @private
    def Base.constanize(word)
      names = word.to_s.gsub(/\/(.?)/) do
        "::#{$1.upcase}"
      end.gsub(/(?:^|_)(.)/) { $1.upcase }.split('::')
      names.shift if names.empty? || names.first.empty?

      constant = Object
      names.each do |name|
        constant = constant.const_defined?(name) ? constant.const_get(name) : constant.const_missing(name)
      end
      constant
    end
    
    def Base.get(api_method, parent, element, parameters = {})
        scrobbler_class = constanize("scrobbler/#{element.to_s}")
        doc = request(api_method, parameters)
        elements = []
        doc.root.children.each do |child|
            next unless child.name == parent.to_s
            child.children.each do |child2|
                next unless child2.name == element.to_s
                elements << scrobbler_class.new_from_libxml(child2)
            end
        end
        elements
    end

    def Base.post_request(api_method, parameters = {}, request_method = 'get')
      Base.request(api_method, parameters, 'post')
    end

    # Execute a request to the Audioscrobbler webservice
    #
    # @param [String,Symbol] api_method The method which shall be called.
    # @param [Hash] parameter The parameters passed as URL params.
    def Base.request(api_method, parameters = {}, request_method = 'get')
      raise ArgumentError unless [String, Symbol].member?(api_method.class)
      raise ArgumentError unless parameters.kind_of?(Hash)

      parameters = {:signed => false}.merge(parameters)
      parameters['api_key'] = @@api_key
      parameters['method'] = api_method.to_s
      paramlist = []
      # Check if we want a signed call and pop :signed
      if parameters.delete :signed
        #1: Sort alphabetically
        params = parameters.sort{|a,b| a[0].to_s<=>b[0].to_s}
        #2: concat them into one string
        str = params.join('')
        #3: Append secret
        str = str + @@secret
        #4: Make a md5 hash
        md5 = Digest::MD5.hexdigest(str)
        params << [:api_sig, md5]
        params.each do |a|
          paramlist << "#{sanitize(a[0])}=#{sanitize(a[1])}"
        end
      else
        parameters.each do |key, value|
          paramlist << "#{sanitize(key)}=#{sanitize(value)}"
        end
      end
      url = '/2.0/?' + paramlist.join('&')
      XML::Document.string(self.connection.send(request_method,url))
    end
    
    def Base.mixins(*args)
      args.each do |arg|
        if arg == :image
          extend Scrobbler::ImageClassFuncs
          include Scrobbler::ImageObjectFuncs
        elsif arg == :streamable
          attr_reader :streamable
          extend StreamableClassFuncs
          include StreamableObjectFuncs
        else
          raise ArgumentError, "#{arg} is not a known mixin"
        end
      end
    end
    
    def populate_data(data = {})
      data.each do |key, value|
        instance_variable_set("@#{key.to_s}", value)
      end
    end

  def get_response(api_method, instance_name, parent, element, params, force=true)
    Base.get(api_method, parent, element, params)
  end

  # Execute a request to the Audioscrobbler webservice
  #
  # @param [String,Symbol] api_method The method which shall be called.
  # @param [Hash] parameter The parameters passed as URL params.
  def request(api_method, parameters = {}, request_method = 'get')
    Base.request(api_method, parameters, request_method)
  end

  # Call a API method
  #
  # @param [String,Symbol] api_method The method which shall be called.
  # @param [Hash] params The parameters passed as URL params.
  # @param [String,Symbol] parent the parent XML node to look for.
  # @param [String,Symbol] elemen The xml node name which shall be converted
  #   into an object.
  def call(api_method, parent, element, params)
    Base.get(api_method, parent, element, params)
  end
end # class Base
end # module Scrobbler
