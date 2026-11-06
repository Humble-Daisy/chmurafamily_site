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
end
