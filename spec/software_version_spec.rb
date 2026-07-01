require 'spec_helper'

describe SoftwareVersion do
  # Version must not depend on its subclasses being loaded: requiring the
  # base file alone has to keep working.
  it 'compares generic versions when only software_version/version is required' do
    lib = File.expand_path('../lib', __dir__)
    script = "require 'software_version/version'; exit(SoftwareVersion::Version.new('1') < '2')"
    expect(system(RbConfig.ruby, '-I', lib, '-e', script)).to be true
  end

  it 'keeps Version <=> Rpm symmetric' do
    generic = SoftwareVersion::Version.new('1.0.1-10.module+el8.1.0+3366+6dfb954c')
    rpm = SoftwareVersion::Rpm.new('1.0.1-10.module+el8+2468+c564cec5')
    expect(generic < rpm).to be true
    expect(rpm > generic).to be true
  end
end
