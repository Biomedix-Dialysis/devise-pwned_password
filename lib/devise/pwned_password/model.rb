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

      included do
        # Reset so that @pwned_count always reflects the last result of calling valid?. It shouldn't
        # be possible to successfully save but have @pwned_count > 0.
        before_validation :reset_pwned

        validate :not_pwned_password, if: :check_pwned_password?
      end

      module ClassMethods
        Devise::Models.config(self, :pwned_password_check_enabled)
        Devise::Models.config(self, :min_password_matches)
        Devise::Models.config(self, :min_password_matches_warn)
        Devise::Models.config(self, :pwned_password_check_on_sign_in)
        Devise::Models.config(self, :pwned_password_open_timeout)
        Devise::Models.config(self, :pwned_password_read_timeout)

        def pwned_password_check_on_sign_in?
          pwned_password_check_enabled &&
          pwned_password_check_on_sign_in
        end
      end

      def check_pwned_password?
        self.class.pwned_password_check_enabled &&
          (Devise.activerecord51? ? will_save_change_to_encrypted_password? : encrypted_password_changed?)
      end

      def pwned?
        pwned_count >= pwned_password_min_matches
      end

      def pwned_count
        @pwned_count ||= 0
      end

      # Returns true if password is present in the PwnedPasswords dataset
      def password_pwned?(password)
        reset_pwned
        options = {
          headers: { "User-Agent" => "devise_pwned_password" },
          read_timeout: self.class.pwned_password_read_timeout,
          open_timeout: self.class.pwned_password_open_timeout
        }
        pwned_password = Pwned::Password.new(password.to_s, options)

        @pwned_count = pwned_password.pwned_count
        pwned_after_password_attempt if respond_to?(:pwned_after_password_attempt)
        pwned?
      rescue Pwned::Error => e # NOTE Pwned::TimeoutError < Pwned::Error
        # This deliberately silently swallows errors and returns false (valid) if there was an error. Most apps won't want to tie the ability to sign up users to the availability of a third-party API.
        pwned_after_error(e) if respond_to?(:pwned_after_error)
        false
      end

      private

        def reset_pwned
          @pwned_count = 0
        end

        def pwned_password_min_matches
          # If you do have a different warning threshold, that threshold will also be used
          # when a user changes their password so that they don't continue to be warned if they
          # choose another password that is in the pwned list but occurs with a frequency below
          # the main threshold that is used for *new* user registrations.
          (self.class.min_password_matches_warn if persisted?) ||
            self.class.min_password_matches
        end

        def not_pwned_password
          if password_pwned?(password)
            errors.add :password, :pwned_password, {count: @pwned_count, user_id: id}
          end
        end
    end
  end
end
