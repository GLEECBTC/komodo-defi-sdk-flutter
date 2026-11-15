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
  s.public_header_files = 'Classes/**/*.h'

  # Ensure source files are included
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'FlutterMacOS'

  # The build transformer extracts verified archive contents into macos/bin.
  # CocoaPods embeds/signs this dynamic library in the application's Frameworks
  # directory. An executable-only archive cannot satisfy native FFI startup.
  s.vendored_libraries = 'bin/libkdflib.dylib'
  s.preserve_paths = ['bin/*', 'bin/.api_last_updated_macos', 'validate_native_library.rb']
  s.script_phase = {
    :name => 'Validate bundled native KDF library',
    :execution_position => :before_compile,
    :script => 'ruby "${PODS_TARGET_SRCROOT}/validate_native_library.rb" "${PODS_TARGET_SRCROOT}"'
  }

  # Configuration for macOS build
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    # Allow building universal macOS apps (arm64 + x86_64). i386 remains excluded by default Xcode settings.
    'OTHER_LDFLAGS' => '-framework SystemConfiguration',
    # Add rpath to ensure dylib can be found at runtime
    'LD_RUNPATH_SEARCH_PATHS' => [
      '$(inherited)',
      '@executable_path/../Frameworks',
      '@loader_path/Frameworks'
    ]
  }

  # Ensure dylibs are properly linked
  s.libraries = ['c++', 'resolv']

  s.platform = :osx, '10.14'
  s.swift_version = '5.0'
end
