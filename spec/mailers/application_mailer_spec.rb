require "rails_helper"

RSpec.describe ApplicationMailer do
  it "queues deliver_later on the mailers queue" do
    expect { MagicLinkMailer.sign_in_link("someone@example.com", "token").deliver_later }
      .to have_enqueued_job.on_queue("mailers")
  end

  # MAIL_FROM is the deployment's sender; without it the address derives from the host (#1318).
  describe "the default sender" do
    let(:user) { create(:user) }
    let(:sender) { MagicLinkMailer.sign_in_link(user.email_address, "token").from }

    around do |example|
      original = ENV["MAIL_FROM"]
      example.run
    ensure
      original.nil? ? ENV.delete("MAIL_FROM") : ENV["MAIL_FROM"] = original
    end

    it "is MAIL_FROM when the deployment sets it" do
      ENV["MAIL_FROM"] = "hello@humbledaisy.com"

      expect(sender).to eq([ "hello@humbledaisy.com" ])
    end

    it "derives noreply at the mailer host otherwise" do
      ENV.delete("MAIL_FROM")

      expect(sender.first).to start_with("noreply@")
    end
  end
end
