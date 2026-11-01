# frozen_string_literal: true

require "rails_helper"
require "kamal"

RSpec.describe "the deployment guide" do
  let(:guide) { Rails.root.join("app/docs/developer/deployment.md").read }
  let(:fenced) { ->(language, marker) { guide.scan(/```#{language}\n(.*?)```/m).flatten.find { |block| block.include?(marker) } } }

  it "reads secrets through fnox in a form Kamal's secrets parser runs" do
    example = fenced.("bash", "fnox get")

    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, ".kamal"))
      File.write(File.join(dir, ".kamal/secrets"), example.to_s)
      fnox = File.join(dir, "fnox")
      File.write(fnox, "#!/bin/sh\necho \"decrypted-$2\"\n")
      File.chmod(0o755, fnox)

      path = ENV.fetch("PATH")
      secrets = begin
        ENV["PATH"] = "#{dir}:#{path}"
        Dir.chdir(dir) { Kamal::Secrets.new.to_h }
      ensure
        ENV["PATH"] = path
      end

      expect(secrets).to include("RAILS_MASTER_KEY" => "decrypted-RAILS_MASTER_KEY")
    end
  end

  it "shows a proxy behind another TLS terminator that Kamal accepts" do
    example = YAML.safe_load(fenced.("yaml", "http_port").to_s).to_h
    kamal_docs = YAML.load_file(File.join(Gem.loaded_specs["kamal"].full_gem_path, "lib/kamal/configuration/docs/proxy.yml"))

    expect(example.dig("proxy", "ssl")).to be(false)
    expect {
      Kamal::Configuration::Validator::Proxy.new(example["proxy"], example: kamal_docs["proxy"], context: "proxy").validate!
    }.not_to raise_error
  end
end
