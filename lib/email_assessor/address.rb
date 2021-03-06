# frozen_string_literal: true
require "email_assessor"
require "resolv"
require "mail"

module EmailAssessor
  class Address
    attr_accessor :address

    PROHIBITED_DOMAIN_PREFIXES = [
      '.',
      '-',
    ].freeze

    PROHIBITED_DOMAIN_CONTENT = [
      '+',
      '!',
      '_',
      '/',
      ' ',
      '..',
      '-.',
      "'",
    ].freeze

    PROHIBITED_DOMAIN_SUFFIXES = [
      # none
    ].freeze

    PROHIBITED_LOCAL_PREFIXES = [
      '.',
    ].freeze

    PROHIBITED_LOCAL_CONTENT = [
      '..',
    ].freeze

    PROHIBITED_LOCAL_SUFFIXES = [
      '.',
    ].freeze

    class << self
      def prohibited_domain_regex
        @prohibited_domain_content_regex ||= make_regex(
          prefixes: PROHIBITED_DOMAIN_PREFIXES,
          content: PROHIBITED_DOMAIN_CONTENT,
          suffixes: PROHIBITED_DOMAIN_SUFFIXES
        )
      end

      def prohibited_local_regex
        @prohibited_local_content_regex ||= make_regex(
          prefixes: PROHIBITED_LOCAL_PREFIXES,
          content: PROHIBITED_LOCAL_CONTENT,
          suffixes: PROHIBITED_LOCAL_SUFFIXES
        )
      end

      private

      def make_regex(prefixes: nil, content: nil, suffixes: nil)
        parts = []

        unless prefixes.nil?
          prefixes.each do |prefix|
            parts << "\\A#{Regexp.escape(prefix)}"
          end
        end

        unless content.nil?
          content.each do |prefix|
            parts << Regexp.escape(prefix)
          end
        end

        unless suffixes.nil?
          suffixes.each do |prefix|
            parts << "#{Regexp.escape(prefix)}\\z"
          end
        end

        Regexp.new(parts.join("|"), Regexp::IGNORECASE)
      end
    end

    def initialize(address)
      @parse_error = false
      @raw_address = address

      begin
        @address = Mail::Address.new(address)
      rescue Mail::Field::ParseError
        @parse_error = true
      end
    end

    def valid?
      return @valid unless @valid.nil?
      return false if @parse_error

      @valid =
        if address.domain && address.address == @raw_address
          domain = address.domain

          domain.include?('.') &&
            !domain.match?(self.class.prohibited_domain_regex) &&
            !address.local.match?(self.class.prohibited_local_regex)
        else
          false
        end
    end

    def disposable?
      valid? && EmailAssessor.domain_is_disposable?(address.domain)
    end

    def blacklisted?
      valid? && EmailAssessor.domain_is_blacklisted?(address.domain)
    end

    def valid_mx?
      valid? && mx_servers.any?
    end

    def mx_server_is_in?(domain_list_file)
      mx_servers.any? do |mx_server|
        return false unless mx_server.respond_to?(:exchange)
        mx_server = mx_server.exchange.to_s

        EmailAssessor.domain_in_file?(mx_server, domain_list_file)
      end
    end

    def mx_servers
      @mx_servers ||= Resolv::DNS.open do |dns|
        mx_servers = dns.getresources(address.domain, Resolv::DNS::Resource::IN::MX)
        (mx_servers.any? && mx_servers) ||
          dns.getresources(address.domain, Resolv::DNS::Resource::IN::A)
      end
    end
  end
end
