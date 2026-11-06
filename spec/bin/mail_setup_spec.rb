require "rails_helper"
require "tmpdir"

load Rails.root.join("bin/mail-setup")

RSpec.describe MailSetup do
  describe MailSetup::CredentialsText do
    let(:login) { { user_name: "u", password: "p" } }

    def parsed(text) = YAML.unsafe_load(text)

    it "appends a block and keeps other keys and comments" do
      after = described_class.with_login("# keep\nsecret_key_base: abc\n", **login)

      expect(after).to include("# keep\n")
      expect(parsed(after)).to eq("secret_key_base" => "abc", "smtp" => { "user_name" => "u", "password" => "p" })
    end

    it "replaces only the smtp block, leaving smtp_broadcast alone" do
      before = "smtp:\n  user_name: old\n  password: old\nsmtp_broadcast:\n  password: other\n# tail\nz: 1\n"
      after = described_class.with_login(before, **login)

      expect(parsed(after).keys).to eq(%w[smtp smtp_broadcast z])
      expect(parsed(after).dig("smtp", "user_name")).to eq("u")
      expect(parsed(after).dig("smtp_broadcast", "password")).to eq("other")
      expect(after).to include("# tail\n")
    end

    it "replaces an inline smtp value" do
      after = described_class.with_login("smtp: {user_name: a, password: b}\nz: 1\n", **login)

      expect(parsed(after)).to eq("smtp" => { "user_name" => "u", "password" => "p" }, "z" => 1)
    end

    it "doesn't duplicate the block on a second run" do
      once = described_class.with_login("z: 1\n", **login)

      expect(described_class.with_login(once, **login)).to eq(once)
    end

    it "starts the block on its own line when the text has no final newline" do
      expect(parsed(described_class.with_login("z: 1", **login)).keys).to eq(%w[z smtp])
    end

    [ "abc #def", "*anchor", "yes", "12345", "{a: 1}", "!ruby/object:Object {}", "x\": y", "ünï" ].each do |value|
      it "round-trips #{value.inspect} exactly" do
        after = described_class.with_login("z: 1\n", user_name: value, password: value)

        expect(parsed(after)["smtp"]).to eq("user_name" => value, "password" => value)
      end
    end

    it "accepts a correct edit" do
      before = "a: 1\n"

      expect(described_class.safe_edit?(before, described_class.with_login(before, **login), **login)).to be(true)
    end

    it "accepts a correct edit of a file with an alias and a date" do
      before = "base: &b\n  a: 1\ncopy: *b\nwhen: 2026-01-01\n"

      expect(described_class.safe_edit?(before, described_class.with_login(before, **login), **login)).to be(true)
    end

    it "refuses an edit that changed another key" do
      expect(described_class.safe_edit?("a: 1\n", %(a: 2\nsmtp:\n  user_name: "u"\n  password: "p"\n), **login)).to be(false)
    end

    it "refuses an edit that changed the value" do
      after = %(a: 1\nsmtp:\n  user_name: "u"\n  password: p #q\n)

      expect(described_class.safe_edit?("a: 1\n", after, user_name: "u", password: "p #q")).to be(false)
    end

    it "refuses text that doesn't parse" do
      expect(described_class.safe_edit?("a: 1\n", "a: b: c\n", **login)).to be(false)
    end
  end

  describe MailSetup::DeployFile do
    let(:real) { Rails.root.join("config/deploy.yml").read }
    let(:values) { { "SMTP_ADDRESS" => "email-smtp.us-east-1.amazonaws.com", "SMTP_PORT" => "587", "MAIL_FROM" => "hi@acme.example" } }
    let(:mail_from_comment) { real.lines.grep(/# MAIL_FROM:/) }

    def clear_values(text) = YAML.safe_load(text, aliases: true).dig("env", "clear")

    it "sets all three values and keeps every other comment" do
      after = described_class.with_values(real, values)

      expect(clear_values(after)).to include("SMTP_ADDRESS" => values["SMTP_ADDRESS"], "SMTP_PORT" => 587, "MAIL_FROM" => "hi@acme.example")
      expect(after.lines.grep(/^\s*#/)).to eq(real.lines.grep(/^\s*#/) - mail_from_comment)
    end

    it "leaves an existing MAIL_FROM alone when none is given" do
      with_sender = described_class.with_values(real, values)
      after = described_class.with_values(with_sender, values.except("MAIL_FROM").merge("SMTP_ADDRESS" => "smtp.example.org"))

      expect(clear_values(after)).to include("MAIL_FROM" => "hi@acme.example", "SMTP_ADDRESS" => "smtp.example.org")
    end

    it "keeps the MAIL_FROM comment when no sender is given" do
      expect(described_class.with_values(real, values.except("MAIL_FROM"))).to include(mail_from_comment.first)
    end

    it "inserts the port and sender directly after the address when they're absent" do
      bare = "env:\n  clear:\n    SMTP_ADDRESS: old.example\n    OTHER: 1\n"
      after = described_class.with_values(bare, values)

      expect(after).to eq("env:\n  clear:\n    SMTP_ADDRESS: email-smtp.us-east-1.amazonaws.com\n    SMTP_PORT: 587\n    MAIL_FROM: hi@acme.example\n    OTHER: 1\n")
    end

    it "keeps a display name intact" do
      after = described_class.with_values(real, values.merge("MAIL_FROM" => "Acme: Sales <hi@acme.example>"))

      expect(clear_values(after)["MAIL_FROM"]).to eq("Acme: Sales <hi@acme.example>")
    end

    it "is editable only with an uncommented SMTP_ADDRESS under env.clear" do
      expect(described_class.editable?(real)).to be(true)
      expect(described_class.editable?("env:\n  clear:\n    # SMTP_ADDRESS: x\n")).to be(false)
      expect(described_class.editable?("env:\n  secret:\n    - SMTP_ADDRESS\n")).to be(false)
      expect(described_class.editable?("other:\n  SMTP_ADDRESS: x\n")).to be(false)
      expect(described_class.editable?("")).to be(false)
      expect(described_class.editable?(":bad: [")).to be(false)
    end

    it "reads the plain values under env.clear" do
      expect(described_class.values(real)).to include("SMTP_ADDRESS" => "smtp.postmarkapp.com")
      expect(described_class.values(":bad: [")).to eq({})
    end

    it "accepts a good edit" do
      expect(described_class.safe_edit?(real, described_class.with_values(real, values), values)).to be(true)
    end

    it "refuses an edit that changed another value" do
      before = "env:\n  clear:\n    SMTP_ADDRESS: a\n    OTHER: 1\n"
      after = "env:\n  clear:\n    SMTP_ADDRESS: b\n    OTHER: 2\n"

      expect(described_class.safe_edit?(before, after, { "SMTP_ADDRESS" => "b" })).to be(false)
    end

    it "refuses an edit that doesn't hold the answer" do
      before = "env:\n  clear:\n    SMTP_ADDRESS: a\n"

      expect(described_class.safe_edit?(before, before, { "SMTP_ADDRESS" => "b" })).to be(false)
    end

    it "refuses an edit that changed anything outside env.clear" do
      before = "service: a\nenv:\n  clear:\n    SMTP_ADDRESS: a\n"
      after = "service: b\nenv:\n  clear:\n    SMTP_ADDRESS: b\n"

      expect(described_class.safe_edit?(before, after, { "SMTP_ADDRESS" => "b" })).to be(false)
    end
  end
end
