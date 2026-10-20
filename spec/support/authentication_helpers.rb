module AuthenticationHelpers
  PASSWORD = "correct horse battery".freeze

  def sign_in(user = User.first || FactoryBot.create(:user), code: nil)
    post session_path, params: { email_address: user.email_address, password: PASSWORD, code: code }.compact
    user
  end
end

RSpec.configure do |config|
  config.include AuthenticationHelpers, type: :request
  config.include ActiveJob::TestHelper
end
