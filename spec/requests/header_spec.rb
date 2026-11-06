require "rails_helper"

RSpec.describe "Header", type: :request do
  describe "hamburger button (mobile menu trigger)" do
    context "authenticated user with unread notifications" do
      let(:user) { create(:user) }
      before do
        sign_in(user)
        PasswordChangedNotifier.with(record: user).deliver(user)
      end

      it "has class `relative` so the absolutely-positioned indicator anchors to the button" do
        get workspaces_path
        doc = Nokogiri::HTML(response.body)
        button = doc.at_css('button[data-mobile-menu-target="button"]')
        expect(button).not_to be_nil, "hamburger button missing from header"
        expect(button["class"]).to match(/\brelative\b/)
      end

      it "renders the notifications_indicator_hamburger turbo-frame inside the button" do
        get workspaces_path
        doc = Nokogiri::HTML(response.body)
        button = doc.at_css('button[data-mobile-menu-target="button"]')
        expect(button.at_css('turbo-frame[id="notifications_indicator_hamburger"]')).not_to be_nil
      end

      it "renders the indicator dot with danger severity inside the hamburger frame" do
        get workspaces_path
        doc = Nokogiri::HTML(response.body)
        frame = doc.at_css('turbo-frame[id="notifications_indicator_hamburger"]')
        dot = frame.at_css('[data-severity="danger"]')
        expect(dot).not_to be_nil
        expect(dot["class"]).to match(/bg-danger-strong/)
      end
    end

    context "authenticated user with NO unread notifications" do
      let(:user) { create(:user) }
      before do
        sign_in(user)
        # sign_in fires SignInFromNewDeviceNotifier (severity :danger) because
        # the test runner is always a "new device" to the user. Clear those so
        # we can assert the empty-state rendering of the indicator frame.
        user.notifications.destroy_all
      end

      it "renders the frame but no visible dot inside it (stable broadcast target)" do
        get workspaces_path
        doc = Nokogiri::HTML(response.body)
        frame = doc.at_css('turbo-frame[id="notifications_indicator_hamburger"]')
        expect(frame).not_to be_nil
        expect(frame.at_css('[data-severity]')).to be_nil
      end
    end

    context "unauthenticated user" do
      it "does not render the notifications indicator frame" do
        get new_session_path
        doc = Nokogiri::HTML(response.body)
        expect(doc.at_css('turbo-frame[id="notifications_indicator_hamburger"]')).to be_nil
      end
    end
  end
end
