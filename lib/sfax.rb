require 'sfax/connection'
require 'sfax/encryptor'
require 'sfax/path'
require 'sfax/version'
require 'faraday'
require 'json'
require 'uri'

module SFax
  class Faxer

    def initialize(username = nil, api_key = nil, vector = nil, encryption_key = nil)
      return if username.nil? && api_key.nil? && vector.nil? && encryption_key.nil?
      @username = username
      @api_key = api_key
      @encryptor = SFax::Encryptor.new(encryption_key, iv: vector)
      @path = SFax::Path.new(encrypted_token, @api_key)
    end

    # Returns encrypted token for sending the fax.
    def encrypted_token
      raw = "Username=#{@username}&ApiKey=#{@api_key}&GenDT=#{Time.now.utc.iso8601}"
      @encryptor.encrypt(raw)
    end

    # Accepts the file to send and sends it to fax_number.
    def send_fax_raw(fax_number, file_or_body, name = "")
      return if file_or_body.nil? || fax_number.nil?

      connection = SFax::Connection.outgoing
      fax = fax_number[-11..-1] || fax_number

      path = @path.send_fax(fax, name)
      body = file_or_body
      begin
        uri = URI.parse(file_or_body)
        body = open(uri.to_s)
      rescue URI::InvalidURIError
        # nothing to do
      end
      response = connection.post path do |req|
        req.body = {}
        req.body['file'] = Faraday::UploadIO.new(body,
          'application/pdf', "#{Time.now.utc.iso8601}.pdf")
      end

      JSON.parse(response.body)
    end


    def send_fax(fax_number, file_or_body, name='')
      resp = send_fax_raw(fax_number, file_or_body, name)
      (resp['SendFaxQueueId'] != -1) ? resp['SendFaxQueueId'] : nil
    end

    # Checks the status (Success, Failure etc.) of the fax with fax_id.
    def fax_status_raw(fax_id)
      return if fax_id.nil?

      connection = SFax::Connection.incoming
      path = @path.fax_status(fax_id)
      response = connection.get path do |req|
        req.body = {}
      end
      JSON.parse(response.body)
    end

    def fax_status(fax_id)
      resp = fax_status_raw(fax_id)
      status_items = resp['RecipientFaxStatusItems'] || []
      success_fax_id = status_items.first['SendFaxQueueId'] unless status_items.empty?
      is_success = resp['isSuccess'] ? true : false
      return success_fax_id, is_success
    end


    # If there are any received faxes, returns an array of fax_ids for those faxes.
    def receive_fax(count)
      fax_count = (count > 500) ? 500 : count
      connection = SFax::Connection.incoming

      path = @path.receive_fax(fax_count.to_s)
      response = connection.get path do |req|
        req.body = {}
      end

      parsed = JSON.parse(response.body)
      has_more_items = parsed['Has_More_Items'] == 'true' ? true : false
      return has_more_items, parsed['InboundFaxItems']
    end

    # If a valid fax_id is received fetches the contents of the fax and returns
    def download_fax(fax_id)
      return if fax_id.nil?

      connection = SFax::Connection.incoming
      path = @path.download_fax(fax_id)
      response = connection.get path
      response.body
    end
  end
end
