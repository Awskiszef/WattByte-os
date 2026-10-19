Pod::Spec.new do |s|
  s.name             = 'wattbyte_system'
  s.version          = '1.0.0'
  s.summary          = 'WattByte platform bridge (public iOS APIs only).'
  s.description      = 'Interface byte counters via getifaddrs, battery state via UIDevice.'
  s.homepage         = 'https://wattbyte.app'
  s.license          = { :type => 'MIT' }
  s.author           = { 'WattByte' => 'hello@wattbyte.app' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  # Privacy manifest of this pod (boot-time API), embedded as a resource bundle like Flutter's own plugins do.
  s.resource_bundles = { 'wattbyte_system_privacy' => ['Resources/PrivacyInfo.xcprivacy'] }
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
