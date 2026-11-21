require 'spec_helper'

RSpec.describe 'bosh_exporter job' do
  let(:template) { 'bin/bosh_exporter_ctl' }
  let(:minimal) do
    { 'bosh_exporter' => { 'bosh' => { 'url' => 'https://10.0.0.6:25555' }, 'metrics' => { 'environment' => 'test' } } }
  end

  it 'renders valid bash with minimal properties' do
    script = render('bosh_exporter', template, minimal)
    expect_valid_bash(script)
    expect(script).not_to include('--sd.processes_regexp', '--sd.file-path')
  end

  it 'renders sd.processes_regexp (regression: used an undefined variable)' do
    props = minimal.merge('bosh_exporter' => minimal['bosh_exporter'].merge('sd' => { 'processes_regexp' => '^(foo|bar)$' }))
    script = render('bosh_exporter', template, props)
    expect_valid_bash(script)
    expect(script).to include(%q[--sd.processes_regexp=\^\(foo\|bar\)\$])
  end

  it 'exports secrets verbatim, even with shell metacharacters' do
    nasty = %q(pa$$w0rd `id` "q" 'x' \n)
    props = minimal.merge('bosh_exporter' => minimal['bosh_exporter'].merge(
      'bosh' => { 'url' => 'https://bosh', 'password' => nasty, 'uaa' => { 'client_secret' => nasty } },
      'web' => { 'auth_password' => nasty },
    ))
    exports = render('bosh_exporter', template, props).lines.grep(/^\s*export BOSH_EXPORTER_/).join
    values = shell_values(exports, 'BOSH_EXPORTER_BOSH_PASSWORD', 'BOSH_EXPORTER_BOSH_UAA_CLIENT_SECRET',
                          'BOSH_EXPORTER_WEB_AUTH_PASSWORD')
    expect(values.values).to all(eq(nasty))
  end

  it 'renders sd file options for each mode' do
    %w[basic detailed].each do |mode|
      props = minimal.merge('bosh_exporter' => minimal['bosh_exporter'].merge('sd' => { 'file_mode' => mode }))
      script = render('bosh_exporter', template, props)
      expect(script).to include('--sd.file-path=')
      expect(script.include?('--sd.file-detailed')).to eq(mode == 'detailed')
    end
  end

  it 'renders certificate files' do
    props = { 'bosh_exporter' => { 'bosh' => { 'ca_cert' => 'CA' }, 'web' => { 'tls_cert' => 'CRT', 'tls_key' => 'KEY' } } }
    expect(render('bosh_exporter', 'config/bosh_ca_cert.pem', props)).to start_with('CA')
    expect(render('bosh_exporter', 'config/web_tls_cert.pem', props)).to start_with('CRT')
    expect(render('bosh_exporter', 'config/web_tls_key.pem', props)).to start_with('KEY')
  end
end
