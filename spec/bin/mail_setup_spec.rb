require "rails_helper"
require "open3"
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

  describe MailSetup::ProductionCredentials do
    let(:app) { build_app_fixture }
    let(:credentials) { described_class.new(root: app.to_s) }
    let(:login) { { user_name: "fake-u", password: "abc #def" } }
    let(:touched_env) { %w[BUNDLE_GEMFILE BOOTSNAP_CACHE_DIR RAILS_MASTER_KEY RAILS_CREDENTIALS_ENV VISUAL] }

    around do |example|
      kept = ENV.to_h.slice(*touched_env)
      ENV["BUNDLE_GEMFILE"] = Rails.root.join("Gemfile").to_s
      ENV["BOOTSNAP_CACHE_DIR"] = Rails.root.join("tmp/cache").to_s
      ENV.delete("RAILS_MASTER_KEY")
      ENV.delete("RAILS_CREDENTIALS_ENV")
      example.run
    ensure
      touched_env.each { |key| ENV[key] = kept[key] }
    end

    after { FileUtils.rm_rf(app.dirname) }

    def build_app_fixture(name: "app")
      root = Pathname.new(Dir.mktmpdir).join(name)
      FileUtils.mkdir_p(root.join("bin"))
      raise "fixture must be outside the checkout" if root.realpath.to_s.start_with?("#{Rails.root.realpath}/")

      %w[config lib].each { |dir| FileUtils.cp_r(Rails.root.join(dir), root) }
      FileUtils.rm_rf(root.join("config/credentials"))
      FileUtils.rm_f([ root.join("config/master.key"), root.join("config/credentials.yml.enc") ])
      %w[bin/rails bin/mail-setup .gitattributes .gitignore].each { |file| FileUtils.cp(Rails.root.join(file), root.join(file)) }
      system(CleanGitEnv::HASH, "git", "-C", root.to_s, "init", "-q", exception: true)
      root
    end

    def raw_write(text)
      env = CleanGitEnv::HASH.merge("VISUAL" => %(#{RbConfig.ruby} -e "File.write(ARGV[0], ENV.fetch('CONTENT'))"), "CONTENT" => text)
      system(env, "bin/rails", "credentials:edit", "--environment", "production", chdir: app.to_s, out: File::NULL, err: File::NULL)
    end

    def show
      IO.popen(CleanGitEnv::HASH, %w[bin/rails credentials:show --environment production], chdir: app.to_s, err: File::NULL, &:read)
    end

    it "creates credentials on a first run without printing anything" do
      expect { expect(credentials.write_login(**login)).to be(true) }.not_to output.to_stdout_from_any_process

      expect(app.join("config/credentials/production.key")).to exist
      expect(app.join("config/credentials/production.yml.enc")).to exist
      expect(credentials.login_matches?(**login)).to be(true)
      expect(show).to include("secret_key_base")
    end

    it "works from a checkout path with a space" do
      spaced = build_app_fixture(name: "my app")

      expect(described_class.new(root: spaced.to_s).write_login(**login)).to be(true)
    ensure
      FileUtils.rm_rf(spaced.dirname)
    end

    it "reports a failed re-run, though Rails exits 0, and keeps the old login" do
      credentials.write_login(**login)
      failing = described_class.new(root: app.to_s)
      allow(failing).to receive(:stand_in_command).and_return("false")

      expect(failing.write_login(user_name: "new", password: "new")).to be(false)
      expect(credentials.login_matches?(**login)).to be(true)
    end

    it "isn't redirected to staging by RAILS_CREDENTIALS_ENV" do
      ENV["RAILS_CREDENTIALS_ENV"] = "staging"

      expect(credentials.write_login(**login)).to be(true)
      expect(app.join("config/credentials/production.yml.enc")).to exist
      expect(app.join("config/credentials/staging.key")).not_to exist
    end

    it "tells a wrong key from invalid YAML" do
      credentials.write_login(**login)
      expect(described_class.new(root: app.to_s).readable).to eq(:readable)

      key = app.join("config/credentials/production.key")
      good = key.read
      key.write("0" * 32)
      expect(described_class.new(root: app.to_s).readable).to eq(:wrong_key)

      key.write(good)
      raw_write("smtp: bad: yaml: here\n")
      expect(described_class.new(root: app.to_s).readable).to eq(:invalid_yaml)
    end

    it "reads a file with an alias and a date, as the app does" do
      raw_write(%(base: &b\n  a: 1\ncopy: *b\nwhen: 2026-01-01\nmailer:\n  from: hi@acme.example\nsmtp:\n  user_name: "u"\n  password: "p"\n))

      expect(credentials.readable).to eq(:readable)
      expect(credentials.login_matches?(user_name: "u", password: "p")).to be(true)
      expect(credentials.mailer_from).to eq("hi@acme.example")
    end

    it "sees a missing login field" do
      raw_write(%(smtp:\n  user_name: "u"\n))

      expect(credentials.login?).to be(false)
    end

    context "with a recording bin/rails" do
      let(:log) { app.join("rails.log") }

      before do
        FileUtils.mv(app.join("bin/rails"), app.join("bin/rails.real"))
        app.join("bin/rails").write(<<~SHIM)
          #!/usr/bin/env ruby
          require "json"; File.write(#{log.to_s.inspect}, JSON.generate(argv: ARGV, env: ENV.to_h) + "\\n", mode: "a")
          exec(File.expand_path("rails.real", __dir__), *ARGV)
        SHIM
        app.join("bin/rails").chmod(0o755)
      end

      def leaks(text, secrets) = secrets.select { |secret| text.include?(secret) }

      it "keeps the login and key out of arguments, environment and deploy.yml" do
        ENV["VISUAL"] = "decoy"
        credentials.write_login(**login)
        credentials.login_matches?(**login)
        key = app.join("config/credentials/production.key").read.strip

        edit = log.readlines.map { |line| JSON.parse(line) }.find { |call| call["argv"].first == "credentials:edit" }

        expect(leaks(log.read + app.join("config/deploy.yml").read, [ login[:user_name], login[:password], key ])).to be_empty
        expect(edit["env"]["VISUAL"]).to include("--write-login")
        expect(edit["env"].key?("RAILS_CREDENTIALS_ENV")).to be(false)
      end

      it "has a scanner that finds a planted secret" do
        log.write("planted-sentinel")

        expect(leaks(log.read, [ "planted-sentinel" ])).to eq([ "planted-sentinel" ])
      end
    end
  end

  describe "bin/mail-setup --write-login" do
    let(:dir) { Pathname.new(Dir.mktmpdir) }
    let(:file) { dir.join("credentials.yml") }

    after { FileUtils.rm_rf(dir) }

    def stand_in(stdin)
      Open3.capture3(RbConfig.ruby, Rails.root.join("bin/mail-setup").to_s, "--write-login", file.to_s, stdin_data: stdin)
    end

    it "writes the login when the edit is safe, printing nothing" do
      file.write("a: 1\n")
      out, err, status = stand_in(%({"user_name":"u","password":"p"}))

      expect([ out, status.exitstatus ]).to eq([ "", 0 ])
      expect(err.lines.grep(/\bp\b/)).to be_empty
      expect(YAML.unsafe_load(file.read)["smtp"]).to eq("user_name" => "u", "password" => "p")
    end

    it "leaves a file it can't edit safely untouched, exits 1 and prints nothing" do
      file.write("a: b: c\n")
      out, _err, status = stand_in(%({"user_name":"FAKESECRET","password":"FAKESECRET"}))

      expect(file.read).to eq("a: b: c\n")
      expect([ out, status.exitstatus ]).to eq([ "", 1 ])
    end

    it "prints no value when its input is broken" do
      file.write("a: 1\n")
      out, err, status = stand_in("FAKESECRET not json")

      expect(file.read).to eq("a: 1\n")
      expect(status.exitstatus).to eq(1)
      expect(out + err).not_to include("FAKESECRET")
    end
  end
end
