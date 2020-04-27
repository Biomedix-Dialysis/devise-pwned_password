# frozen_string_literal: true

require "pwned"
require "devise/pwned_password/hooks/pwned_password"

module Devise
  module Models
    # The PwnedPassword module adds a new validation for Devise Models.
    # No modifications to routes or controllers needed.
    # Simply add :pwned_password to the list of included modules in your
    # devise module, and all new registrations will be blocked if they use
    # a password in this dataset https://haveibeenpwned.com/Passwords.
    module PwnedPassword
      extend ActiveSupport::Concern

      module ClassMethods
        Devise::Models.config(self, :min_password_matches)
        Devise::Models.config(self, :min_password_matches_warn)
        Devise::Models.config(self, :pwned_password_check_on_sign_in)
        Devise::Models.config(self, :pwned_password_open_timeout)
        Devise::Models.config(self, :pwned_password_read_timeout)
      end

      included do
        validates :password, not_pwned: {
          threshold: min_password_matches,
          request_options: {
            open_timeout: pwned_password_open_timeout,
            read_timeout: pwned_password_read_timeout,
            headers: { "User-Agent" => "devise_pwned_password" }
          }
        }
        validate :not_pwned_password_warn
      end

      def pwned?
        @pwned ||= false
      end

      def pwned_count
        @pwned_count ||= 0
      end
      attr_writer :pwned_count

      # Returns true if password is present in the PwnedPasswords dataset
      def password_pwned?(password)
puts %(pwned_count=#{(pwned_count).inspect})
puts %(persisted?=#{(persisted?).inspect})
          puts %(self.class.min_password_matches_warn=#{(self.class.min_password_matches_warn).inspect})
          @pwned = @pwned_count >= (persisted? ? self.class.min_password_matches_warn || self.class.min_password_matches : self.class.min_password_matches)
          return @pwned
      end

      private

        def not_pwned_password_warn
          # This deliberately fails silently on 500's etc. Most apps won't want to tie the ability to sign up users to the availability of a third-party API.
          if password_pwned?(password)
            errors.add(:password, :pwned_password, count: @pwned_count)
          end
        end
    end
  end
end
