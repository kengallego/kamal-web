require "rails_helper"

RSpec.describe User do
  it "orders roles so higher roles can do everything lower roles can" do
    admin = build(:user, :admin)
    viewer = build(:user, :viewer)

    expect(admin.can?("deployer")).to be true
    expect(viewer.can?("viewer")).to be true
    expect(viewer.can?("deployer")).to be false
  end

  it "requires passwords of at least 10 characters" do
    expect(build(:user, password: "short")).not_to be_valid
  end

  it "keeps at least one admin" do
    admin = create(:user, :admin)

    expect(admin.update(role: "viewer")).to be false
    expect(admin.reload.destroy).to be false

    create(:user, :admin)
    expect(admin.reload.update(role: "viewer")).to be true
  end
end
