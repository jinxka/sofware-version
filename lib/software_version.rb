require 'software_version/version'
require 'software_version/rpm'

module SoftwareVersion
end

# Convert the argument into a SoftwareVersion::Version.
def SoftwareVersion(version)
  SoftwareVersion::Version(version)
end
