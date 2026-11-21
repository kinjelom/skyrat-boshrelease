require 'bosh/template/test'
require 'yaml'
require 'open3'
require 'tmpdir'
require 'fileutils'
require 'shellwords'

RELEASE_DIR = File.expand_path('..', __dir__)

module SkyratHelpers
  def release
    @release ||= Bosh::Template::Test::ReleaseDir.new(RELEASE_DIR)
  end

  # `template` is the rendered path from the job spec (e.g. 'config/bpm.yml').
  def render(job_name, template, props = {}, consumes = [])
    release.job(job_name).template(template).render(props, consumes: consumes)
  end

  # Fails the example when `bash -n` reports a syntax error.
  def expect_valid_bash(script)
    _out, err, status = Open3.capture3('bash', '-n', stdin_data: script)
    expect(status).to be_success, "bash syntax error:\n#{err}\n---\n#{script}"
  end

  # Evaluates the given shell lines and returns the value of each requested variable,
  # exactly as the shell sees it after quoting/expansion.
  def shell_values(lines, *vars)
    probe = vars.map { |v| %(printf '%s\\0' "${#{v}-__UNSET__}") }.join("\n")
    out, err, status = Open3.capture3('bash', '-c', "set -eu\n#{lines}\n#{probe}")
    raise "shell failed: #{err}" unless status.success?
    vars.zip(out.split("\0")).to_h
  end

  # Long options used in rendered text (after the first `exec`, if present).
  def rendered_flags(text)
    text = text.split(/^\s*exec\s/, 2).last
    text.scan(/(?<=\s|^)--([a-z0-9][a-z0-9._-]*)/).flatten.uniq
  end

  # Long options and env var names accepted by a binary, according to its --help.
  def binary_help(binary)
    out, _status = Open3.capture2e(binary, '--help')
    {
      text: out,
      flags: out.scan(/--(?:\[no-\])?([a-z0-9][a-z0-9._-]*)/).flatten.uniq,
      envs: out.scan(/\$([A-Z][A-Z0-9_]+)/).flatten.uniq,
    }
  end
end

# Builds a package the way the BOSH compile VM does: copies files matched by the
# package spec (from src/ and blobs/) into a compile dir and runs `packaging`.
module PackagingHelpers
  def self.build(package_name, install_root)
    spec = YAML.load_file(File.join(RELEASE_DIR, 'packages', package_name, 'spec'))
    compile = Dir.mktmpdir("compile-#{package_name}-")
    install = File.join(install_root, package_name)
    FileUtils.mkdir_p(install)

    Array(spec['files']).each do |glob|
      matches = %w[src blobs].flat_map do |base|
        root = File.join(RELEASE_DIR, base)
        Dir.glob(glob, base: root).map { |rel| [root, rel] }
      end
      raise "package #{package_name}: no file matches '#{glob}' (blobs synced?)" if matches.empty?

      matches.each do |root, rel|
        next if File.directory?(File.join(root, rel))
        FileUtils.mkdir_p(File.join(compile, File.dirname(rel)))
        FileUtils.cp(File.join(root, rel), File.join(compile, rel))
      end
    end

    env = { 'BOSH_COMPILE_TARGET' => compile, 'BOSH_INSTALL_TARGET' => install }
    script = File.join(RELEASE_DIR, 'packages', package_name, 'packaging')
    out, status = Open3.capture2e(env, 'bash', script, chdir: compile)
    raise "packaging #{package_name} failed:\n#{out}" unless status.success?

    install
  ensure
    FileUtils.rm_rf(compile) if compile
  end

  def self.blobs_present?
    YAML.load_file(File.join(RELEASE_DIR, 'config', 'blobs.yml')).keys.all? do |path|
      File.exist?(File.join(RELEASE_DIR, 'blobs', path))
    end
  end
end

RSpec.configure do |config|
  config.include SkyratHelpers
  config.disable_monkey_patching!
  config.order = :defined
end
