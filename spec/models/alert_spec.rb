require "rails_helper"

RSpec.describe Alert do
  let(:project) { create(:project, name: "shop", notification_webhook_url: "https://hooks.example.com/x") }

  it "opens, keeps and resolves an alert, notifying both changes" do
    expect {
      Alert.track(project, "disk", "192.0.2.10", failing: true, message: "93%")
    }.to have_enqueued_job(AlertNotificationJob).with(an_instance_of(Alert), "opened")

    expect {
      Alert.track(project, "disk", "192.0.2.10", failing: true, message: "95%")
      Alert.track(project, "disk", "192.0.2.10", failing: nil)
    }.not_to have_enqueued_job(AlertNotificationJob)
    expect(project.alerts.active.sole.message).to eq("95%")

    expect {
      Alert.track(project, "disk", "192.0.2.10", failing: false)
    }.to have_enqueued_job(AlertNotificationJob).with(an_instance_of(Alert), "resolved")
    expect(project.alerts.active).to be_empty
  end

  it "doesn't notify without a webhook" do
    project.update!(notification_webhook_url: nil)

    expect { Alert.track(project, "memory", "192.0.2.10", failing: true) }.not_to have_enqueued_job(AlertNotificationJob)
    expect(project.alerts.active.count).to eq(1)
  end

  it "prunes resolved alerts after a while" do
    old = project.alerts.create!(kind: "disk", subject: "a", opened_at: 40.days.ago, resolved_at: 40.days.ago)
    open = project.alerts.create!(kind: "disk", subject: "b", opened_at: 40.days.ago)

    Alert.prune!
    expect(Alert.all).to eq([ open ])
    expect { old.reload }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it "formats notifications" do
    alert = project.alerts.create!(kind: "disk", subject: "192.0.2.10", message: "93%", opened_at: 1.hour.ago)
    job = AlertNotificationJob.new

    project.update!(notification_format: "slack")
    expect(job.payload(alert, "opened")[:text]).to eq("🚨 shop: Disk almost full on 192.0.2.10 (93%)")

    alert.update!(resolved_at: Time.current)
    expect(job.payload(alert, "resolved")[:text]).to start_with("✅ Resolved for shop: Disk almost full on 192.0.2.10")

    project.update!(notification_format: "generic")
    expect(job.payload(alert, "opened")).to include(event: "alert.opened", project: "shop", kind: "disk", message: "93%")
  end
end
