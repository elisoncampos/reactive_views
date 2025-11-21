# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ReactiveViews::TempFileManager do
  describe '.write' do
    let(:content) { '<div>Hello</div>' }
    let(:identifier) { 'TestComponent' }

    it 'writes the content to a temp file inside Rails tmp directory' do
      temp_file = described_class.write(content, identifier: identifier, extension: 'tsx')

      expect(File).to exist(temp_file.path)
      expect(File.read(temp_file.path)).to eq(content)
      expect(temp_file.path).to include('tmp/reactive_views_full_page')
      expect(File.extname(temp_file.path)).to eq('.tsx')
    ensure
      temp_file&.delete
    end

    it 'deletes the file when delete is called' do
      temp_file = described_class.write(content, identifier: identifier, extension: 'tsx')
      temp_file.delete

      expect(File).not_to exist(temp_file.path)
    end
  end

  describe '.prune' do
    it 'removes files older than the max age' do
      temp_file = described_class.write('<div>Old</div>', identifier: 'OldComponent', extension: 'tsx')
      File.utime(Time.now - 3600, Time.now - 3600, temp_file.path)

      described_class.prune(max_age_seconds: 10)

      expect(File).not_to exist(temp_file.path)
    end
  end
end
