require "rails_helper"

RSpec.describe "Notifications index page", type: :system do
  let(:password) { "SecureP@ssw0rd123!" }
  let(:user) { create(:user, password: password) }

  # Monotonic per-example offset: every dispatch lands 5 minutes after the
  # previous one, so each notification gets a distinct idempotency bucket
  # without relying on rand. Same pattern as
  # spec/requests/account/notifications_spec.rb. See project memory
  # `project_flaky_tests_followup.md` for the rand-bucket-collision history:
  # 1/1000 collisions would dedup-drop retries and flake "renders only unread"
  # assertions.
  def deliver_security_notification(recipient = user)
    @notification_offset ||= 0
    @notification_offset += 5
    travel_to(Time.current + @notification_offset.minutes) do
      PasswordChangedNotifier.with(record: recipient).deliver(recipient)
    end
    recipient.notifications.order(:id).last
  end

  before { sign_in_via_form(user) }

  describe "discoverability (v2: canonical path is the user-menu Notifications row)" do
    it "exposes a Notifications link inside the user-menu dropdown" do
      visit new_session_path
      find("#user-menu-button").click
      within "#user-menu" do
        expect(page).to have_link(I18n.t("navigation.notifications"), href: settings_notifications_path)
      end
    end
  end

  # #919: every notifier defines a url and no in-app surface rendered it; the
  # row now links its message there, and a deleted-record notification (the
  # placeholder contract) renders plain text with no dead href.
  describe "row link to the notification's destination (#919)" do
    # The recipient is the inviter, a member of the workspace, as in the app;
    # the members page the link lands on is workspace-scoped.
    def deliver_resent_invitation
      workspace = create(:workspace)
      create(:membership, :owner, user: user, workspace: workspace)
      invitation = create(:invitation, invitable: workspace, email: "invitee@example.com", invited_by: user)
      @notification_offset ||= 0
      @notification_offset += 5
      travel_to(Time.current + @notification_offset.minutes) do
        WorkspaceInvitationResentNotifier.with(record: invitation).deliver(user)
      end
      [ invitation, user.notifications.order(:id).last ]
    end

    it "links the message to the notifier's url and follows it" do
      invitation, notification = deliver_resent_invitation

      # The link text is the message; built from I18n here rather than by
      # calling notification.message on the spec's own (un-preloaded) object,
      # which Bullet would flag as the page's N+1.
      message = I18n.t("notifications.workspace_invitation_resent.message",
                       invitee_email: invitation.email, workspace_name: invitation.invitable.name)

      visit settings_notifications_path
      within("##{ActionView::RecordIdentifier.dom_id(notification)}") do
        click_link message
      end

      # The resent notifier's url is the workspace's members page; the page
      # renders it from preloaded records, so the row link is the only query.
      expect(page).to have_current_path(workspace_members_path(invitation.invitable))
    end

    it "renders a deleted-record notification as placeholder text with no link" do
      invitation, notification = deliver_resent_invitation
      invitation.destroy

      visit settings_notifications_path
      within("##{ActionView::RecordIdentifier.dom_id(notification)}") do
        expect(page).to have_text(I18n.t("notifications.placeholder"))
        expect(page).to have_no_css("a[href]")
      end
    end

    it "passes AAA in both themes with a linked row" do
      _invitation, notification = deliver_resent_invitation
      visit settings_notifications_path
      expect(page).to have_css("##{ActionView::RecordIdentifier.dom_id(notification)} a[href]")
      expect(axe_violations_in_both_themes).to be_empty
    end
  end

  describe "GET /account/notifications" do
    it "renders the heading and a list row containing each notification's message" do
      notification = deliver_security_notification
      expected_message = I18n.t(
        "notifications.password_changed.message",
        user_name: user.first_name
      )

      visit settings_notifications_path

      expect(page).to have_css("h1", text: I18n.t("notifications.index.heading"))
      within "##{ActionView::RecordIdentifier.dom_id(notification)}" do
        expect(page).to have_text(expected_message)
      end
    end

    describe "filter chips" do
      it "marks the All chip as current by default" do
        deliver_security_notification

        visit settings_notifications_path

        within "[aria-label='#{I18n.t('notifications.index.filters_aria')}']" do
          expect(page).to have_link(
            I18n.t("notifications.index.filters.all"),
            href: settings_notifications_path
          )
          all_chip = find_link(I18n.t("notifications.index.filters.all"))
          expect(all_chip["aria-current"]).to eq("page")
        end
      end

      it "filters to only unread when Unread chip is followed" do
        read_notification = deliver_security_notification
        read_notification.update!(read_at: Time.current)
        unread_notification = deliver_security_notification

        visit settings_notifications_path
        click_link I18n.t("notifications.index.filters.unread")

        expect(page).to have_css("##{ActionView::RecordIdentifier.dom_id(unread_notification)}")
        expect(page).not_to have_css("##{ActionView::RecordIdentifier.dom_id(read_notification)}")
      end
    end

    describe "per-row controls" do
      it "marks an unread row as read via Turbo Stream and swaps the button" do
        notification = deliver_security_notification

        visit settings_notifications_path

        within "##{ActionView::RecordIdentifier.dom_id(notification)}" do
          click_button I18n.t("notifications.index.item.mark_read")
          expect(page).to have_button(I18n.t("notifications.index.item.mark_unread"))
        end
        expect(notification.reload.read_at).to be_present
      end

      it "marks a read row as unread via Turbo Stream" do
        notification = deliver_security_notification
        notification.update!(read_at: Time.current)

        visit settings_notifications_path

        within "##{ActionView::RecordIdentifier.dom_id(notification)}" do
          click_button I18n.t("notifications.index.item.mark_unread")
          expect(page).to have_button(I18n.t("notifications.index.item.mark_read"))
        end
        expect(notification.reload.read_at).to be_nil
      end
    end

    describe "row controls" do
      it "gives each row exactly one control and puts no destructive control on the page" do
        notification = deliver_security_notification

        visit settings_notifications_path

        expect(page).to have_css("button.btn-secondary", text: I18n.t("notifications.index.mark_all_read.action"))
        within "##{ActionView::RecordIdentifier.dom_id(notification)}" do
          expect(page).to have_css("button[type='submit']", count: 1)
          expect(page).to have_css("button.btn-secondary[type='submit']", count: 1)
        end
        # Anchored by the positive assertions above (absence_assertions_are_anchored).
        expect(page).not_to have_css("button.btn-outline-danger")
      end
    end

    describe "bulk actions" do
      it "marks every unread notification as read after confirming the bulk modal" do
        unread_a = deliver_security_notification
        unread_b = deliver_security_notification

        visit settings_notifications_path
        click_button I18n.t("notifications.index.mark_all_read.action")
        within "dialog[open]" do
          click_button I18n.t("notifications.index.mark_all_read.action")
        end

        # #941: the confirmation reaches the acting tab through the pill live
        # region after the redirect (a mutation, per #901), not as page content.
        expect(page).to have_css("#toast-pills [role='status']", text: I18n.t("settings.notification_readings.create.success"))
        expect(unread_a.reload.read_at).to be_present
        expect(unread_b.reload.read_at).to be_present
      end
    end

    describe "retention hint" do
      def set_retention(someone, days)
        # preferences! (#884): a plain create here raced the sign-in timezone
        # beacon into a second row the page never read (#949).
        row = someone.preferences!
        row.update!(notification_preferences: row.notification_preferences.merge("retention_days" => days))
      end

      it "states the user's own retention in the same words the preferences page uses" do
        set_retention(user, 365)

        visit settings_notifications_path

        expect(page).to have_text("Once you've read a notification, we remove it 1 year later.")
        expect(page).to have_text("Unread notifications stay until you read them.")
      end

      it "states the default for a user with untouched preferences" do
        visit settings_notifications_path

        expect(page).to have_text("we remove it 90 days later")
      end

      it "links straight to the retention control" do
        visit settings_notifications_path
        click_link "Change retention"

        expect(page).to have_current_path(edit_settings_notification_preferences_path)
        expect(page.current_url).to end_with("#retention-days")
        expect(page).to have_css("select#retention-days", visible: true)
      end

      it "shows the hint on the empty state too" do
        # Sign-in dispatches a SignInFromNewDeviceNotifier (same clearing as
        # spec/system/notification_preferences_spec.rb) — without it the list
        # is never actually empty and this example proves nothing.
        user.notifications.destroy_all

        visit settings_notifications_path

        expect(page).to have_text(I18n.t("notifications.index.empty_all"))
        expect(page).to have_link("Change retention")
      end
    end

    # axe-core WCAG 2.2 AAA, both themes, asserted here since the retention
    # hint added this page's first text-interactive link; members_table_spec
    # audits a different surface, so it is not a substitute for this check.
    it "passes automated accessibility checks with a populated list (light + dark)" do
      deliver_security_notification
      visit settings_notifications_path
      page.execute_script("document.querySelectorAll('[data-controller=\"toast-pill\"], [data-controller=\"toast-card\"]').forEach(el => el.remove())")

      expect(axe_clean_in_both_themes?).to be(true),
        "Accessibility violations found:\n#{axe_violations_in_both_themes.join("\n")}"
    end
  end
end
