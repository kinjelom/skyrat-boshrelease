require 'spec_helper'

RSpec.describe 'blackbox_exporter job' do
  it 'renders valid bash with defaults and all optional properties' do
    expect_valid_bash(render('blackbox_exporter', 'bin/blackbox_exporter_ctl'))
    props = { 'blackbox_exporter' => {
      'history_limit' => 100, 'log_level' => 'debug', 'log_format' => 'json', 'timeout_offset' => 0.5,
      'web' => { 'route_prefix' => '/bb', 'external_url' => 'https://bb.example.com' },
    }, 'env' => { 'http_proxy' => 'http://proxy:3128', 'https_proxy' => 'http://proxy:3128', 'no_proxy' => 'localhost' } }
    script = render('blackbox_exporter', 'bin/blackbox_exporter_ctl', props)
    expect_valid_bash(script)
    expect(script).to include('--history.limit="100"', '--web.route-prefix="/bb"', 'export HTTPS_PROXY="http://proxy:3128"')
  end

  it 'renders the default modules config as YAML' do
    config = YAML.safe_load(render('blackbox_exporter', 'config/blackbox.yml'))
    expect(config['modules'].keys).to include('http_2xx', 'tcp_connect', 'icmp')
  end
end

RSpec.describe 'pushgateway job' do
  it 'renders valid bash with defaults' do
    script = render('pushgateway', 'bin/pushgateway_ctl.sh')
    expect_valid_bash(script)
    expect(script).to include('--web.listen-address=":9091"', '--persistence.file=')
    expect(script).not_to include('--push.disable-consistency-check', '--push.enable-utf8-names')
  end

  it 'renders boolean switches when true' do
    script = render('pushgateway', 'bin/pushgateway_ctl.sh',
                    'pushgateway' => { 'push' => { 'disable_consistency_check' => true, 'enable_utf8_names' => true } })
    expect_valid_bash(script)
    expect(script).to include('--push.disable-consistency-check', '--push.enable-utf8-names')
  end

  it 'renders the web config as YAML' do
    web = { 'basic_auth_users' => { 'admin' => '$2y$10$hash' } }
    expect(YAML.safe_load(render('pushgateway', 'config/web.yaml', 'pushgateway' => { 'web' => { 'config' => web } }))).to eq(web)
    expect(YAML.safe_load(render('pushgateway', 'config/web.yaml'))).to eq({})
  end
end

RSpec.describe 'watchdog_exporter job' do
  it 'renders the config, including the spec example endpoints, as YAML' do
    example = YAML.load_file(File.join(RELEASE_DIR, 'jobs/watchdog_exporter/spec'))
                  .dig('properties', 'watchdog_exporter.endpoints', 'example')
    config = YAML.safe_load(render('watchdog_exporter', 'config/watchdog.yml',
                                   'watchdog_exporter' => { 'endpoints' => example }))
    expect(config['settings']).to include('listen-address' => '0.0.0.0:9321', 'probe-interval' => '1m', 'debug' => false)
    expect(config['metrics']).to eq('namespace' => 'watchdog', 'environment' => 'unknown')
    expect(config['routes']).to eq('direct' => {})
    expect(config['endpoints']).to eq(example)
  end

  it 'renders the bpm config' do
    bpm = YAML.safe_load(render('watchdog_exporter', 'config/bpm.yml'))
    expect(bpm['processes'].first['args']).to eq(['--config', '/var/vcap/jobs/watchdog_exporter/config/watchdog.yml'])
  end
end
