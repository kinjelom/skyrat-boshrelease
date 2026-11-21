require 'spec_helper'

RSpec.describe 'firehose_to_syslog job' do
  let(:required) do
    {
      'firehose_to_syslog' => {
        'cloudfoundry' => {
          'api_endpoint' => 'https://api.sys.example.com',
          'firehose_client_secret' => 'secret',
        },
      },
    }
  end

  # Runs the rendered script with the binary replaced by printf, returning the real argv.
  def argv_of(script)
    stubbed = script
              .sub(%r{^exec /var/vcap/packages/firehose_to_syslog/bin/firehose_to_syslog}) { "printf '%s\\0'" }
              .sub(/^wait_for_service_on_port .*$/, ':')
              .gsub(/^echo .*$/, ':')
    out, err, status = Open3.capture3('bash', '-c', stubbed)
    raise "script failed: #{err}" unless status.success?
    out.split("\0")
  end

  describe 'bin/firehose_to_syslog.sh' do
    let(:template) { 'bin/firehose_to_syslog.sh' }

    it 'renders valid bash that starts with a shebang and execs the binary' do
      script = render('firehose_to_syslog', template, required)
      expect(script.lines.first).to eq("#!/bin/bash\n")
      expect(script).to match(%r{^exec /var/vcap/packages/firehose_to_syslog/bin/firehose_to_syslog \\$})
      expect_valid_bash(script)
    end

    it 'does not pass boolean switches whose value is the default false' do
      argv = argv_of(render('firehose_to_syslog', template, required))
      expect(argv).not_to include('--skip-ssl-validation', '--skip-ssl-validation-syslog',
                                  '--debug', '--ignore-missing-apps', '--enable-stats-server')
    end

    it 'passes boolean switches when set to true' do
      props = required.dup
      props['firehose_to_syslog'] = required['firehose_to_syslog'].merge(
        'debug' => true,
        'enable_stats_server' => true,
        'cloudfoundry' => required['firehose_to_syslog']['cloudfoundry'].merge(
          'skip_ssl_validation' => true, 'ignore_missing_apps' => true,
        ),
        'syslog' => { 'skip_ssl_validation' => true },
      )
      argv = argv_of(render('firehose_to_syslog', template, props))
      expect(argv).to include('--skip-ssl-validation', '--skip-ssl-validation-syslog',
                              '--debug', '--ignore-missing-apps', '--enable-stats-server')
    end

    it 'passes values with shell metacharacters verbatim' do
      nasty = %q(s3cr$t `id` "q" 'x' ;&|)
      props = { 'firehose_to_syslog' => { 'cloudfoundry' => {
        'api_endpoint' => 'https://api.sys.example.com',
        'firehose_client_secret' => nasty,
        'orgs' => ['org a', 'org-b'],
        'extra_fields' => { 'env' => 'dev x' },
      } } }
      argv = argv_of(render('firehose_to_syslog', template, props))
      expect(argv).to include("--client-secret=#{nasty}")
      expect(argv).to include('--orgs=org a,org-b')
      expect(argv).to include('--extra-fields=env:dev x')
    end

    it 'expands job paths and renders the defaults' do
      props = required.merge('firehose_to_syslog' => required['firehose_to_syslog'].merge(
        'syslog' => { 'cert_pem' => 'PEM', 'host' => 'syslog.local', 'port' => 6514, 'protocol' => 'tcp+tls' },
      ))
      argv = argv_of(render('firehose_to_syslog', template, props))
      expect(argv).to include(
        '--boltdb-path=/var/vcap/store/firehose_to_syslog/data/firehose_to_syslog.cache.db',
        '--cert-pem-syslog=/var/vcap/jobs/firehose_to_syslog/config/cert.pem',
        '--syslog-server=syslog.local:6514',
        '--syslog-protocol=tcp+tls',
        '--events=LogMessage',
        '--client-id=firehose-to-syslog',
      )
    end
  end

  describe 'config/bpm.yml' do
    it 'is valid YAML' do
      bpm = YAML.safe_load(render('firehose_to_syslog', 'config/bpm.yml', required))
      expect(bpm['processes'].first['executable']).to eq('/var/vcap/jobs/firehose_to_syslog/bin/firehose_to_syslog.sh')
    end
  end
end
