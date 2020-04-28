# frozen_string_literal: true

require "test_helper"

class Devise::PwnedPassword::Test < ActiveSupport::TestCase
  class WhenPwned < Devise::PwnedPassword::Test
    test "should deny validation and set pwned_count" do
      user = pwned_password_user
      assert_not user.valid?
      assert_match /\Ahas appeared in a data breach \d{7,} times\z/, user.errors[:password].first
      assert user.pwned_count > 0
    end

    test "when pwned_count < min_password_matches, is considered valid" do
      user = pwned_password_user
      User.min_password_matches = 999_999_999
      assert user.valid?
      assert user.pwned_count > 0
    end

    test "when pwned_count = min_password_matches, is considered invalid" do
      user = pwned_password_user
      pwned_password = Minitest::Mock.new
      pwned_password.expect :pwned_count, 1
      User.min_password_matches = 1
      Pwned::Password.stub :new, pwned_password do
        assert_not user.valid?
      end
      pwned_password.verify
    end

    test "when pwned_password_check_enabled = false, is considered valid" do
      user = pwned_password_user
      Devise.pwned_password_check_enabled = false
      assert user.valid?
      assert_equal 0, user.pwned_count
    end

    test "when using with_pwned_password_check, enables the check, is considered invalid" do
      user = pwned_password_user
      Devise.pwned_password_check_enabled = false
      assert user.valid?
      with_pwned_password_check do
        assert_not user.valid?
        assert user.pwned_count > 0
        without_pwned_password_check do
          assert user.valid?
          assert_equal 0, user.pwned_count
        end
      end
    end

    test "pwned_after_password_attempt should be called after any password attempts" do
      user = pwned_password_user
      was_called = false
      callback_args = nil
      user.singleton_class.class_eval do
        define_method(:pwned_after_password_attempt) { |*args|
          was_called = true
          callback_args = args
        }
      end
      user.save
      assert was_called
      assert_equal [pwned_password], callback_args
    end
  end

  class WhenNotPwned < Devise::PwnedPassword::Test
    test "should accept validation and set pwned_count" do
      user = valid_password_user
      assert user.valid?
      assert_equal 0, user.pwned_count
    end

    test "when password changed to a pwned password: should add error if pwned_count > min_password_matches_warn || pwned_count > min_password_matches" do
      user = valid_password_user

      # *not* pwned_count > min_password_matches_warn
      password = "password"
      user.update password: password, password_confirmation: password
      User.min_password_matches_warn = 999_999_999
      assert user.valid?
      assert_not user.pwned_count > User.min_password_matches_warn

      # pwned_count > min_password_matches_warn
      User.min_password_matches_warn = 1
      User.min_password_matches      = 999_999_999
      assert_not user.valid?
      assert user.pwned_count > User.min_password_matches_warn
    end
  end

  class WhenError < Devise::PwnedPassword::Test
    test "pwned_after_error should be called after any pwned errors during operation" do
      user = valid_password_user
      was_called = false
      user.singleton_class.class_eval do
        define_method(:pwned_after_password_attempt) { |*|
          raise Pwned::TimeoutError, "some timeout error"
        }
        define_method(:pwned_after_error) { |e|
          was_called = e.is_a?(Pwned::Error)
        }
      end
      user.save
      assert was_called
    end
  end
end
