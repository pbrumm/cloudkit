require 'openid/store/interface'
module CloudKit

  # An OpenIDStore provides the interface expected by the ruby-openid gem,
  # mapping it to a CloudKit::Store instance.
  class OpenIDStore < OpenID::Store::Interface
    @@store = nil

    # Initialize an OpenIDStore.
    def initialize
      unless @@store
        @@store = Store.new(
          :collections => [:cloudkit_openid_associations, :cloudkit_openid_nonces])
      end
    end

    def get_association(server_url, handle=nil) #:nodoc:
      options = {:server_url => server_url}
      options.merge!(:handle => Base64.encode64(handle)) if (handle && handle != '')
      result = @@store.get(CloudKit::URI.new('/cloudkit_openid_associations'), options)
      return nil unless result.status == 200
      return nil if result.parsed_content['total'] == 0

      associations = result.parsed_content['documents'].map {|data| JSON.parse(data['document'])}
      return nil if associations.empty?

      associations.sort_by{|a| a['issued']}
      a = associations[-1]
      OpenID::Association.new(
        Base64.decode64(a['handle']),
        Base64.decode64(a['secret']),
        Time.at(a['issued']),
        a['lifetime'],
        a['assoc_type'])
    end

    def remove_association(server_url, handle) #:nodoc:
      result = @@store.get(
        CloudKit::URI.new('/cloudkit_openid_associations'),
        :server_url => server_url,
        :handle     => Base64.encode64(handle))
      return nil unless result.status == 200

      associations = result.parsed_content['documents'].map {|data| data['document']}
      return nil if associations.empty?

      uris = result.parsed_content['documents'].map {|data| data['uri']}
      result.parsed_content['documents'].each_with_index do |r, index|
        @@store.delete(CloudKit::URI.new(uris[index]), :etag => r['etag'])
      end
    end

    def store_association(server_url, association) #:nodoc:
      remove_association(server_url, association.handle)
      json = JSON.generate(
        :server_url => server_url,
        :handle     => Base64.encode64(association.handle),
        :secret     => Base64.encode64(association.secret),
        :issued     => association.issued.to_i,
        :lifetime   => association.lifetime,
        :assoc_type => association.assoc_type)
      result = @@store.post(CloudKit::URI.new('/cloudkit_openid_associations'), :json => json)
      return (result.status == 201)
    end

    def use_nonce(server_url, timestamp, salt) #:nodoc:
      return false if (timestamp - Time.now.to_i).abs > OpenID::Nonce.skew

      fragment = ::URI.escape(
        [server_url, timestamp, salt].join('-'), 
        Regexp.union(::URI::REGEXP::UNSAFE, '/', ':'))
      uri    = "/cloudkit_openid_nonces/#{fragment}"
      result = @@store.put(CloudKit::URI.new(uri), :json => '{}')
      return (result.status == 201)
    end

    def self.cleanup #:nodoc:
      # TODO
    end

    def self.cleanup_associations #:nodoc:
      # TODO
    end

    def self.cleanup_nonces #:nodoc:
      # TODO
    end

    # Return the version number for this store.
    def version; 1; end

  end
end
