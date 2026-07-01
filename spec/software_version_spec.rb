require 'spec_helper'

describe SoftwareVersion do
  # Version must not depend on its subclasses being loaded: requiring the
  # base file alone has to keep working.
  it 'compares generic versions when only software_version/version is required' do
    lib = File.expand_path('../lib', __dir__)
    script = "require 'software_version/version'; " \
             "exit(SoftwareVersion::Version.new('1') < SoftwareVersion::Version.new('2'))"
    expect(system(RbConfig.ruby, '-I', lib, '-e', script)).to be true
  end
end
