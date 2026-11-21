require 'spec_helper'

# Builds every package from the local blobs and checks that the flags/env vars our
# job templates pass are accepted by the packaged binary. Catches broken packaging
# scripts and CLI changes after a blob version bump.
#
# Requires blobs in blobs/ (`bosh sync-blobs`) and a linux-amd64 host.
RSpec.describe 'packages', :packaging do
  before(:all) do
    skip 'blobs missing, run `bosh sync-blobs`' unless PackagingHelpers.blobs_present?
    @install_root = Dir.mktmpdir('skyrat-packages-')
  end

  after(:all) { FileUtils.rm_rf(@install_root) if @install_root }

  def build(pkg)
    @built ||= {}
    @built[pkg] ||= PackagingHelpers.build(pkg, @install_root)
  end

  def help_of(pkg, bin = pkg)
    binary = File.join(build(pkg), 'bin', bin)
    expect(File.executable?(binary)).to be(true), "#{binary} is not executable"
    binary_help(binary)
  end

  def expect_flags_supported(used, help, pkg)
    unknown = used - help[:flags]
    expect(unknown).to be_empty, "#{pkg} does not accept: #{unknown.join(', ')}\n#{help[:text]}"
  end

  def expect_envs_supported(used, help, pkg)
    unknown = used - help[:envs]
    expect(unknown).to be_empty, "#{pkg} does not read env vars: #{unknown.join(', ')}"
  end

  it 'builds the common package' do
    expect(File.exist?(File.join(build('common'), 'utils.sh'))).to be(true)
  end

  it 'blackbox_exporter accepts all rendered flags' do
    script = render('blackbox_exporter', 'bin/blackbox_exporter_ctl', 'blackbox_exporter' => {
      'history_limit' => 1, 'log_level' => 'info', 'log_format' => 'json', 'timeout_offset' => 0.5,
      'web' => { 'route_prefix' => '/', 'external_url' => 'http://x' },
    })
    expect(File.exist?(File.join(build('blackbox_exporter'), 'common', 'utils.sh'))).to be(true)
    expect_flags_supported(rendered_flags(script), help_of('blackbox_exporter'), 'blackbox_exporter')
  end

  it 'blackbox_exporter accepts the default modules config' do
    Dir.mktmpdir do |dir|
      cfg = File.join(dir, 'blackbox.yml')
      File.write(cfg, render('blackbox_exporter', 'config/blackbox.yml'))
      bin = File.join(build('blackbox_exporter'), 'bin', 'blackbox_exporter')
      out, status = Open3.capture2e(bin, "--config.file=#{cfg}", '--config.check')
      expect(status).to be_success, out
    end
  end

  it 'bosh_exporter accepts all rendered flags and env vars' do
    script = render('bosh_exporter', 'bin/bosh_exporter_ctl', 'bosh_exporter' => {
      'bosh' => { 'url' => 'https://b', 'username' => 'u', 'password' => 'p', 'log_level' => 'INFO', 'ca_cert' => 'CA',
                  'uaa' => { 'client_id' => 'c', 'client_secret' => 's' } },
      'filter' => { 'deployments' => 'a', 'azs' => 'z1', 'collectors' => 'Jobs', 'cidrs' => '10.0.0.0/8' },
      'log_format' => 'logger:stdout', 'log_level' => 'info', 'metrics' => { 'environment' => 'e' },
      'sd' => { 'file_mode' => 'detailed', 'processes_regexp' => '.*' },
      'web' => { 'auth_username' => 'u', 'auth_password' => 'p', 'tls_cert' => 'C', 'tls_key' => 'K' },
    })
    help = help_of('bosh_exporter')
    expect_flags_supported(rendered_flags(script), help, 'bosh_exporter')
    expect_envs_supported(script.scan(/export (BOSH_EXPORTER_[A-Z_]+)=/).flatten, help, 'bosh_exporter')
  end

  it 'boshi_exporter accepts all rendered flags' do
    script = render('boshi_exporter', 'bin/boshi_exporter_ctl')
    expect(File.exist?(File.join(build('boshi_exporter'), 'common', 'pid_utils.sh'))).to be(true)
    expect_flags_supported(rendered_flags(script), help_of('boshi_exporter'), 'boshi_exporter')
  end

  it 'cf_exporter accepts all rendered args and env vars' do
    process = YAML.safe_load(render('cf_exporter', 'config/bpm.yml', 'cf_exporter' => {
      'cf' => { 'api_url' => 'https://a', 'username' => 'u', 'password' => 'p', 'client_id' => 'c',
                'client_secret' => 's', 'deployment_name' => 'cf' },
      'filter' => { 'collectors' => 'Applications' }, 'metrics' => { 'namespace' => 'cf', 'environment' => 'e' },
      'skip_ssl_verify' => true,
      'web' => { 'telemetry_path' => '/m', 'auth_username' => 'u', 'auth_password' => 'p', 'tls_cert' => 'C', 'tls_key' => 'K' },
    }))['processes'].first
    help = help_of('cf_exporter')
    expect_flags_supported(process['args'].grep(/\A--/).map { |a| a.delete_prefix('--') }, help, 'cf_exporter')
    expect_envs_supported(process['env'].keys.grep(/\ACF_EXPORTER_/), help, 'cf_exporter')
  end

  it 'firehose_exporter reads all rendered env vars' do
    process = YAML.safe_load(render('firehose_exporter', 'config/bpm.yml', 'firehose_exporter' => {
      'logging' => { 'url' => 'rlp:8082' }, 'skip_ssl_verify' => true, 'log_in_json' => true,
      'metrics' => { 'environment' => 'test' },
      'profiler' => { 'enable' => true },
      'web' => { 'auth_username' => 'u', 'auth_password' => 'p', 'tls_cert' => 'C', 'tls_key' => 'K' },
    }))['processes'].first
    expect_envs_supported(process['env'].keys.grep(/\AFIREHOSE_EXPORTER_/), help_of('firehose_exporter'), 'firehose_exporter')
  end

  it 'firehose_to_syslog accepts all rendered flags' do
    script = render('firehose_to_syslog', 'bin/firehose_to_syslog.sh', 'firehose_to_syslog' => {
      'debug' => true, 'enable_stats_server' => true,
      'cloudfoundry' => { 'api_endpoint' => 'https://a', 'firehose_client_secret' => 's', 'doppler_endpoint' => 'wss://d',
                          'skip_ssl_validation' => true, 'ignore_missing_apps' => true, 'orgs' => ['o'],
                          'app_name_suffixes_to_strip' => ['-blue'], 'extra_fields' => { 'a' => 'b' } },
      'syslog' => { 'cert_pem' => 'PEM', 'skip_ssl_validation' => true },
    })
    expect_flags_supported(rendered_flags(script), help_of('firehose_to_syslog'), 'firehose_to_syslog')
  end

  it 'pushgateway accepts all rendered flags' do
    script = render('pushgateway', 'bin/pushgateway_ctl.sh', 'pushgateway' => {
      'web' => { 'external_url' => 'http://x', 'route_prefix' => '/' },
      'push' => { 'disable_consistency_check' => true, 'enable_utf8_names' => true },
    })
    expect(File.exist?(File.join(build('pushgateway'), 'common', 'utils.sh'))).to be(true)
    expect_flags_supported(rendered_flags(script), help_of('pushgateway'), 'pushgateway')
  end

  it 'watchdog_exporter is packaged and runnable' do
    binary = File.join(build('watchdog_exporter'), 'bin', 'watchdog_exporter')
    expect(File.executable?(binary)).to be(true)
    out, _ = Open3.capture2e(binary, '-h')
    expect(out).to include('-config')
  end
end
