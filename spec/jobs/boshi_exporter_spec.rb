require 'spec_helper'

RSpec.describe 'boshi_exporter job' do
  let(:template) { 'bin/boshi_exporter_ctl' }

  it 'renders valid bash with defaults' do
    script = render('boshi_exporter', template)
    expect_valid_bash(script)
    expect(script).to include('--web.listen-address ":9191"', '--metrics.namespace "boshi"')
  end

  it 'exports env values verbatim, even with quotes' do
    nasty = %q(it's "quoted" $HOME `id`)
    script = render('boshi_exporter', template, 'boshi_exporter' => { 'env' => { 'FOO' => nasty, 'NUM' => 5 } })
    expect_valid_bash(script)
    exports = script.lines.grep(/^\s*export (FOO|NUM)=/).join
    expect(shell_values(exports, 'FOO', 'NUM')).to eq('FOO' => nasty, 'NUM' => '5')
  end
end
