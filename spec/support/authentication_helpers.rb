module AuthenticationHelpers
  def sign_in
    post session_path, params: { password: AccessPassword::DEVELOPMENT_PASSWORD }
  end
end

RSpec.configure do |config|
  config.include AuthenticationHelpers, type: :request
  config.include ActiveJob::TestHelper
end
