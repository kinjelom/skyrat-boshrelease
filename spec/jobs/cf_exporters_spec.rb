require 'spec_helper'

RSpec.describe 'cf_exporter job' do
  let(:required) { { 'cf_exporter' => { 'cf' => { 'api_url' => 'https://api.sys.example.com' } } } }

  def bpm(props)
    YAML.safe_load(render('cf_exporter', 'config/bpm.yml', props))['processes'].first
  end

  it 'renders bpm config with string args and env values' do
    process = bpm(required)
    expect(process['executable']).to eq('/var/vcap/packages/cf_exporter/bin/cf_exporter')
    expect(process['args']).to all(be_a(String))
    expect(process['env'].values).to all(be_a(String))
    expect(process['args'].each_slice(2).to_h).to include('--cf.api_url' => 'https://api.sys.example.com',
                                                          '--collector.workers' => '10')
    expect(process['env']).not_to have_key('CF_EXPORTER_SKIP_SSL_VERIFY')
  end

  it 'maps optional properties to env vars' do
    props = { 'cf_exporter' => {
      'cf' => { 'api_url' => 'https://api', 'client_id' => 'id', 'client_secret' => 's', 'deployment_name' => 'cf' },
      'metrics' => { 'environment' => 'prod' }, 'skip_ssl_verify' => true,
      'web' => { 'tls_cert' => 'CRT', 'tls_key' => 'KEY' },
    }, 'env' => { 'https_proxy' => 'http://proxy' } }
    env = bpm(props)['env']
    expect(env).to include('CF_EXPORTER_CF_CLIENT_SECRET' => 's', 'CF_EXPORTER_METRICS_ENVIRONMENT' => 'prod',
                           'CF_EXPORTER_SKIP_SSL_VERIFY' => 'true', 'HTTPS_PROXY' => 'http://proxy',
                           'CF_EXPORTER_WEB_TLS_CERTFILE' => '/var/vcap/jobs/cf_exporter/config/web_tls_cert.pem')
  end
end

RSpec.describe 'firehose_exporter job' do
  let(:rlp_link) do
    Bosh::Template::Test::Link.new(
      name: 'reverse_log_proxy',
      address: 'rlp.service.cf.internal',
      instances: [Bosh::Template::Test::LinkInstance.new(address: 'rlp.service.cf.internal')],
      properties: { 'reverse_log_proxy' => { 'egress' => { 'port' => 8082 } } },
    )
  end

  def bpm(props, consumes = [])
    props = { 'firehose_exporter' => { 'metrics' => { 'environment' => 'test' } } }
            .merge(props) { |_, a, b| a.merge(b) }
    YAML.safe_load(render('firehose_exporter', 'config/bpm.yml', props, consumes))['processes'].first
  end

  it 'takes the log proxy URL from the reverse_log_proxy link' do
    env = bpm({}, [rlp_link])['env']
    expect(env['FIREHOSE_EXPORTER_LOGGING_URL']).to eq('rlp.service.cf.internal:8082')
    expect(env['FIREHOSE_EXPORTER_NODE_INDEX']).to eq('0')
    expect(env.values).to all(be_a(String))
    expect(env).not_to have_key('FIREHOSE_EXPORTER_SKIP_SSL_VERIFY')
  end

  it 'falls back to firehose_exporter.logging.url' do
    env = bpm('firehose_exporter' => { 'logging' => { 'url' => 'rlp:8082' }, 'skip_ssl_verify' => true })['env']
    expect(env).to include('FIREHOSE_EXPORTER_LOGGING_URL' => 'rlp:8082', 'FIREHOSE_EXPORTER_SKIP_SSL_VERIFY' => 'true')
  end

  it 'fails to render without a link or url' do
    expect { bpm({}) }.to raise_error(Bosh::Template::UnknownProperty)
  end
end
