Pod::Spec.new do |s|
  s.name             = 'DetourAttribution'
  s.version          = '1.1.2'
  s.summary          = 'Install and conversion attribution for the Detour iOS SDK.'

  s.description      = <<-DESC
    Adds attribution to the Detour iOS SDK. Installed next to Detour; an app
    with Detour alone links no attribution framework.
  DESC

  s.homepage         = 'https://github.com/software-mansion-labs/ios-detour'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Software Mansion' => 'contact@godetour.dev' }
  s.source           = {
    :git => 'https://github.com/software-mansion-labs/ios-detour.git',
    :tag => s.version.to_s
  }

  s.ios.deployment_target = '15.0'
  s.swift_version         = '5.5'

  s.source_files = 'Sources/DetourAttribution/**/*.swift'
  s.dependency 'Detour', s.version.to_s
  s.frameworks = 'StoreKit', 'AdServices', 'AdSupport', 'AppTrackingTransparency'
  # Weak, so an app that supports iOS before 17.4 still launches there without the framework.
  s.weak_frameworks = 'AdAttributionKit'

  s.resource_bundles = {
    'DetourAttribution' => ['Sources/DetourAttribution/Resources/PrivacyInfo.xcprivacy']
  }
end
