Pod::Spec.new do |s|
  s.name             = 'Detour'
  s.version          = '0.1.0'
  s.summary          = 'Native iOS SDK for deferred deep links and analytics.'
  s.description      = <<-DESC
Detour iOS SDK for deferred deep links, runtime deep-link processing, and analytics.
                       DESC
  s.homepage         = 'https://godetour.dev'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Software Mansion' => 'contact@godetour.dev' }
  s.source           = { :git => 'https://github.com/software-mansion-labs/ios-detour.git', :tag => s.version.to_s }

  s.platform         = :ios, '13.0'
  s.swift_version    = '5.5'

  s.source_files     = 'Sources/Detour/**/*.swift'
end
