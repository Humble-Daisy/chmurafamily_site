require "rails_helper"

RSpec.describe "The documented recipe for a second kind of mail" do
  let(:base_settings) do
    MailDelivery.smtp_settings({ "SMTP_ADDRESS" => "t.example" }, { smtp: { user_name: "tu", password: "tp" } })
  end

  def mailer_with(settings)
    Class.new(ApplicationMailer) do
      self.delivery_method = :smtp
      self.smtp_settings = settings
      self.deliver_later_queue_name = :low

      def hello = mail(to: "a@example.com", subject: "s", body: "b")
    end
  end

  def smtp_settings_of(mailer) = mailer.hello.message.delivery_method.settings

  before do
    stub_const("BroadcastProbeMailer", mailer_with(base_settings.merge(address: "br.example", user_name: "bu", password: "bp")))
  end

  it "sends through its own settings and leaves its siblings alone" do
    stub_const("SiblingProbeMailer", mailer_with(base_settings))

    expect(smtp_settings_of(BroadcastProbeMailer)).to include(address: "br.example", user_name: "bu")
    expect(smtp_settings_of(SiblingProbeMailer)).to include(address: "t.example", user_name: "tu")
    expect(ApplicationMailer.smtp_settings[:address]).not_to eq("br.example")
  end

  it "has a nil login, not the transactional one, when its settings are blank" do
    stub_const("BlankProbeMailer", mailer_with(base_settings.merge(address: nil, user_name: nil, password: nil)))

    expect(smtp_settings_of(BlankProbeMailer)).to include(user_name: nil, password: nil)
  end

  it "uses a queue the workers claim, and not sign-in mail's" do
    expect(BroadcastProbeMailer.deliver_later_queue_name).to eq(:low)
    expect(Rails.root.join("config/queue.yml").read).to match(/queues: \[.*\blow\b.*\]/)
    expect(ApplicationMailer.deliver_later_queue_name).to eq(:mailers)
  end
end
