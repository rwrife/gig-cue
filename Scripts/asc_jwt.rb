#!/usr/bin/env ruby
# Mint ASC ES256 JWT; JWS needs raw 64-byte r||s, not DER.
require 'base64'
require 'json'
require 'openssl'

key = OpenSSL::PKey::EC.new(File.read(ENV.fetch('ASC_KEY_FILE')))
def b64(value)
  Base64.urlsafe_encode64(value, padding: false)
end

header = b64({alg: 'ES256', kid: ENV.fetch('ASC_KEY_ID'), typ: 'JWT'}.to_json)
payload = b64({iss: ENV.fetch('ASC_ISSUER_ID'), aud: 'appstoreconnect-v1',
               iat: Time.now.to_i, exp: Time.now.to_i + 600}.to_json)
message = "#{header}.#{payload}"
asn1 = OpenSSL::ASN1.decode(key.dsa_sign_asn1(OpenSSL::Digest::SHA256.digest(message)))
r, s = asn1.value.map { |n| n.value.to_i }
signature = [r, s].map { |n| [n.to_s(16).rjust(64, '0')].pack('H*') }.join
abort 'Invalid ES256 signature width' unless signature.bytesize == 64
puts "#{message}.#{b64(signature)}"
