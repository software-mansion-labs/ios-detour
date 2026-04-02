Pod::Spec.new do |s|
  s.name             = 'Detour'
  s.version          = File.read(File.join(__dir__, 'Sources/Detour/Resources/detour_sdk_version.txt')).strip
  s.summary          = 'SDK for handling deferred links and deep links in native iOS apps.'

  s.description      = <<-DESC
    Detour iOS SDK provides seamless handling of deferred links and deep links
    in native iOS applications, including link resolution, runtime handling,
    and analytics.
  DESC

  s.homepage         = 'https://github.com/software-mansion-labs/ios-detour'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Software Mansion' => 'contact@godetour.dev' }
  s.source           = {
    :git => 'https://github.com/software-mansion-labs/ios-detour.git',
    :tag => s.version.to_s
  }

  s.ios.deployment_target = '13.0'
  s.swift_version         = '5.5'

  s.source_files = 'Sources/Detour/**/*.swift'
  s.resources = 'Sources/Detour/Resources/*'
end
