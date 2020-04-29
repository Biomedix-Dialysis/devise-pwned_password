# Devise::PwnedPassword
Devise extension that checks user passwords against the PwnedPasswords dataset (https://haveibeenpwned.com/Passwords).

This handles the 3 use cases listed in [Troy Hunt's article](https://www.troyhunt.com/introducing-306-million-freely-downloadable-pwned-passwords/):
1. Registration/sign-up
2. Password change
3. User log-in (optional)

It checks for compromised ("pwned") passwords in the following ways:
1. It adds a standard model validation to your Devise (`User`) model using [pwned](https://github.com/philnash/pwned). This:
   - prevents new users from being created (signing up) with a compromised password
   - prevents existing users from changing their password to a password that is known to be compromised
2. (Optionally) Whenever a user signs in, checks if their current password is compromised and shows a warning if it is.

Recently the HaveIBeenPwned API has moved to an [authenticated/paid model](https://www.troyhunt.com/authentication-and-the-have-i-been-pwned-api/), but this does not affect the PwnedPasswords API; no payment or authentication is required.


## Usage
Add the `:pwned_password` module to your existing Devise model.

```ruby
class AdminUser < ApplicationRecord
  devise :database_authenticatable,
         :recoverable, :rememberable, :trackable, :validatable, :pwned_password
end
```

Users will receive the following error message if they use a password from the
PwnedPasswords dataset:

```
Password has previously appeared in a data breach and should never be used. Please choose something harder to guess.
```

## Configuration

You can customize this error message by modifying the `devise` YAML file.

```yml
# config/locales/devise.en.yml
en:
  errors:
    messages:
      pwned_password: "has previously appeared in a data breach and should never be used. If you've ever used it anywhere before, change it immediately!"
```

By default passwords are rejected if they appear at all in the data set.
Optionally, you can add the following snippet to `config/initializers/devise.rb`
if you want the error message to be displayed only when the password is present
a certain number of times in the data set:

```ruby
# Minimum number of times a pwned password must exist in the data set in order
# to be reject.
config.min_password_matches = 10
```

By default responses from the PwnedPasswords API are timed out after 5 seconds
to reduce potential latency problems.
Optionally, you can add the following snippet to `config/initializers/devise.rb`
to control the timeout settings:

```ruby
config.pwned_password_open_timeout = 1
config.pwned_password_read_timeout = 2
```


### How to warn existing users when they sign in

You can optionally warn existing users when they sign in if they are using a password from the PwnedPasswords dataset.

To enable this, you _must_ override `after_sign_in_path_for`, like this:

```ruby
# app/controllers/application_controller.rb

  def after_sign_in_path_for(resource)
    if resource.respond_to?(:pwned?) && resource.pwned?
      set_flash_message! :alert, :warn_pwned, {count: resource.pwned_count, user_id: resource.id}
    end
    super
  end
```

For an [Active Admin](https://github.com/activeadmin/activeadmin) application the following monkey patch is needed:

```ruby
# config/initializers/active_admin_devise_sessions_controller.rb
class ActiveAdmin::Devise::SessionsController
  def after_sign_in_path_for(resource)
    if resource.respond_to?(:pwned?) && resource.pwned?
      set_flash_message! :alert, :warn_pwned, {count: resource.pwned_count, user_id: resource.id}
    end
    super
  end
end
```

To prevent the default call to the HaveIBeenPwned API on user sign-in (only
really useful if you're going to check `pwned?` after sign-in as used above),
add the following to `config/initializers/devise.rb`:

```ruby
config.pwned_password_check_on_sign_in = false
```

#### Customize warning message

The default message is:
```
Your password has previously appeared in a data breach and should never be used. We strongly recommend you change your password.
```

You can customize this message by modifying the `devise.en.yml` locale file.

```yml
# config/locales/devise.en.yml
en:
  devise:
    sessions:
      warn_pwned: "Your password has previously appeared in a data breach and should never be used. We strongly recommend you change your password everywhere you have used it."
```

https://www.troyhunt.com/introducing-306-million-freely-downloadable-pwned-passwords/ offers some
good advice for how to implement the user interface in a way that both follows the NIST's guidelines
and provides a good user experience.

If you want to copy the message recommended in that article, here is a template you can use:

```yml
# config/locales/devise.en.yml
en:
  devise:
    sessions:
      warn_pwned:
        The password you're using on this site has previously appeared in a data breach of another site. <b>This is not related to a security incident on this site</b>; however, the fact that it has previously appeared elsewhere puts this account at risk. You should change your password here on the <a href="/users/%{user_id}/edit">change password</a> page as well as on any other site where you've used it. <a href="/pages/how-to-protect-your-account" target="_blank">Read more about how we help protect your account.</a>
```

Keep in mind, though, that including hyperlinks in a validation error message or flash message does
not work out of the box because Rails will escape any HTML by default, so you may have to to work
around this by calling `.html_safe` on the error message in any view templates where you display it
to the user.  Just keep in mind that blindly calling `.html_safe` is unsafe; if any of the message
could come from arbitrary user input, you must take appropriate steps to escape it and prevent [HTML
injection](https://guides.rubyonrails.org/security.html#html-javascript-injection). (See also [these
tips about using
`.html_safe`](https://makandracards.com/makandra/2579-everything-you-know-about-html_safe-is-wrong).)


#### Customize the warning threshold

By default the same value, `config.min_password_matches` is used as the threshold for rejecting a passwords for _new_ user sign-ups and for warning existing users.

If you want to use different thresholds for rejecting the password and warning
the user (for example you may only want to reject passwords that are common but
warn if the password occurs at all in the list), you can set a different value for each.

To change the threshold used for the warning _only_, add to `config/initializers/devise.rb`

```ruby
# Minimum number of times a pwned password must exist in the data set in order
# to warn the user.
config.min_password_matches_warn = 1
```

Note: If you do have a different warning threshold, that threshold will also be used
when a user changes their password (added as an _error_!) so that they don't
continue to be warned if they choose another password that is in the pwned list
but occurs with a frequency below the main threshold that is used for *new*
user registrations (`config.min_password_matches`).

### Disabling in test environments

Because calling a remote API can slow down tests, and requiring non-pwned passwords can make test fixtures needlessly complex (dynamically generated passwords), you probably want to disable the `pwned_password` check in your tests. You can disable the `pwned_password` check for the test environments by adding this to your `config/initializers/devise.rb` file:

```ruby
config.pwned_password_check_enabled = !Rails.env.test?
```

If there are any tests that required the check to be enabled (such as tests for specifically testing the flow/behavior for what should happen when a user does try to use, or already have, a pwned password), you can temporarily set `Devise.pwned_password_check_enabled = true` for the duration of the test (just be sure to reset it back at the end).

To make it easier to turn this check on or off, a `with_pwned_password_check` (and complimentary `without_pwned_password_check`) method is provided:

```ruby
  it "doesn't let you change your password to a compromised password" do
    fill_in 'user_password', with: 'Password'
    with_pwned_password_check do
      click_button 'Save changes'
    end
  end
```

To use these helpers, add to your `test/test_helper.rb` or `spec/spec_helper.rb`:

```ruby
require 'devise/pwned_password/test_helpers'
```

If using RSpec, that's all you need to do: It will automaticaly include the helper methods and reset `pwned_password_check_enabled` to false before every example.

If using Minitest, you also need to add:
```ruby
  include ::Devise::PwnedPassword::TestHelpers::InstanceMethods
```


## Installation
Add this line to your application's Gemfile:

```ruby
gem 'devise-pwned_password'
```

And then execute:
```bash
$ bundle install
```

## Considerations

A few things to consider/understand when using this gem:

* User passwords are hashed using SHA-1 and then truncated to 5 characters,
  implementing the k-Anonymity model described in
  https://haveibeenpwned.com/API/v2#SearchingPwnedPasswordsByRange
  Neither the clear-text password nor the full password hash is ever transmitted
  to a third party. More implementation details and important caveats can be
  found in https://blog.cloudflare.com/validating-leaked-passwords-with-k-anonymity/

* This puts an external API in the request path of users signing up to your application. This could
  potentially add some latency to this operation. The gem is designed to silently swallows errors if
  the PwnedPasswords service is unavailable, allowing users to use compromised passwords during the
  time when it is unavailable.

## Contributing

To contribute:

* Check the [issue tracker](https://github.com/michaelbanfield/devise-pwned_password/issues) and [pull requests](https://github.com/michaelbanfield/devise-pwned_password/pulls) for anything similar
* Fork the repository
* Make your changes
* Run `bin/test` to make sure the unit tests still run
* Send a pull request

## Inspiration

This gem was based on [devise-uncommon_password](https://github.com/HCLarsen/devise-uncommon_password).

## License
The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).
