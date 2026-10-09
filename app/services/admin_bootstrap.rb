# Creates the first admin on an empty instance from ADMIN_EMAIL and
# ADMIN_PASSWORD. When the password is left empty a random one is generated and
# printed once to the container logs; it is never stored in plain text.
class AdminBootstrap
  DEFAULT_EMAIL = "admin@example.com".freeze

  def initialize(email: ENV["ADMIN_EMAIL"], password: ENV["ADMIN_PASSWORD"], io: $stdout)
    @email = email.presence || DEFAULT_EMAIL
    @password = password.presence
    @io = io
  end

  def call
    return if User.exists?

    password = @password || SecureRandom.base58(20)
    user = User.create!(email_address: @email, password: password, name: "Admin", role: "admin")
    announce(user, generated: @password.nil? ? password : nil)
    user
  end

  private
    def announce(user, generated:)
      lines = [ "Kamal UI admin account created", "  Email:    #{user.email_address}" ]
      if generated
        lines << "  Password: #{generated}"
        lines << "  This password is shown only once. Change it after signing in."
      else
        lines << "  Password: the value of ADMIN_PASSWORD"
      end

      width = lines.map(&:length).max + 4
      @io.puts "=" * width, *lines.map { |line| "  #{line}" }, "=" * width
      @io.flush
    end
end
