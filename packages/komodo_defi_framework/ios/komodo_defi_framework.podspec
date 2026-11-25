#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint komodo_defi_framework.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'komodo_defi_framework'
  s.version          = '0.0.1'
  s.summary          = 'A new Flutter FFI plugin project.'
  s.description      = <<-DESC
A new Flutter FFI plugin project.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }

  # This will ensure the source files in Classes/ are included in the native
  # builds of apps using this FFI plugin. Podspec does not support relative
  # paths, so Classes contains a forwarder C file that relatively imports
  # `../src/*` so that the C sources can be shared among all target platforms.
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'
  s.swift_version = '5.0'

  s.frameworks = [
    'CoreFoundation',
    'SystemConfiguration',
  ]

  s.vendored_libraries = 'libkdf.a'
  # s.vendored_libraries = 'libkdflib.dylib'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'OTHER_LDFLAGS' => [
      '-force_load "$(PODS_TARGET_SRCROOT)/libkdf.a"',
      '-framework SystemConfiguration',
    ],
    # # Add rpath to ensure dylib can be found at runtime
    #  'LD_RUNPATH_SEARCH_PATHS' => [
    #   '$(inherited)',
    #   '@executable_path/Frameworks',
    #   '@loader_path/Frameworks'
    # ]
  }

  s.user_target_xcconfig = {
    'OTHER_LDFLAGS' => [
      '-framework SystemConfiguration'
    ]
  }

  s.libraries = ['c++', 'resolv']

end