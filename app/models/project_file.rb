# A file written into the workspace before every command, for things that are
# never committed such as config/master.key or a .kamal/secrets override.
class ProjectFile < ApplicationRecord
  belongs_to :project

  encrypts :content

  normalizes :path, with: ->(p) { p.strip.delete_prefix("./") }

  validates :path, presence: true, uniqueness: { scope: :project_id }
  validate :path_stays_inside_workspace

  private
    def path_stays_inside_workspace
      return if path.blank?

      if path.start_with?("/") || path.split("/").include?("..") || path.start_with?(".git/") || path == ".git"
        errors.add(:path, "must be a relative path inside the project")
      end
    end
end
