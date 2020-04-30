module Factories
  def create_user(password:)
    User.create(email: "example@example.org", password: password, password_confirmation: password)
  end

  def pwned_password
    'password'
  end

  # Tries to create but fails to save due to pwned_password
  def pwned_password_user
    create_user(password: pwned_password)
  end

  # Simulates having a password that was previously valid but is now compromised
  def pwned_password_user!
    user = pwned_password_user
    user.save(validate: false)
    user
  end

  def valid_password
    'fddkasnsdddghjt'
  end

  def valid_password_user
    user = create_user(password: valid_password)
    assert_equal 0, user.errors.size
    user
  end
end

class ActiveSupport::TestCase
  include Factories
end
