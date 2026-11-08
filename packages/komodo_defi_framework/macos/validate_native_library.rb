# Validates the same immutable artifact marker/runtime digest as the SDK build
# transformer before CocoaPods embeds the credential-bearing native engine.
require 'digest'
require 'json'
require 'open3'

def validate_native_kdf(macos_dir, architectures: ENV.fetch('ARCHS', '').split)
  binary_dir = File.join(macos_dir, 'bin')
  library = File.join(binary_dir, 'libkdflib.dylib')
  unless File.file?(library) && !File.symlink?(library)
    raise 'Missing verified macOS bin/libkdflib.dylib. The pinned KDF archive must include a native library; an executable-only archive cannot be used for wallet credentials.'
  end

  manifest = JSON.parse(File.read(File.join(macos_dir, '..', 'app_build', 'build_config.json'))).fetch('api')
  platform = manifest.fetch('platforms').fetch('macos')
  marker = JSON.parse(File.read(File.join(binary_dir, '.api_last_updated_macos')))
  commit = manifest.fetch('api_commit_hash')
  checksums = platform.fetch('valid_zip_sha256_checksums').sort
  unless commit.match?(/\A[a-f0-9]{40}\z/) && marker.fetch('api_commit_hash') == commit &&
         !checksums.empty? && checksums.all? { |value| value.match?(/\A[a-f0-9]{64}\z/) && value != '0' * 64 } &&
         marker.fetch('checksums').sort == checksums && checksums.include?(marker.fetch('archive_sha256')) &&
         Regexp.new(platform.fetch('matching_pattern')).match?(marker.fetch('archive_filename'))
    raise 'The macOS KDF artifact provenance does not match the immutable build manifest.'
  end

  runtime_names = %w[kdf mm2 libkdf.a libmm2.a libkdflib.a libmm2.dylib libkdflib.dylib]
  runtime_files = runtime_names.map do |name|
    candidate = File.join(binary_dir, name)
    raise 'Linked KDF runtime files are not allowed.' if File.symlink?(candidate)
    [name, Digest::SHA256.file(candidate).hexdigest] if File.file?(candidate)
  end.compact.sort_by(&:first)
  entrypoints = runtime_files.select { |name, _| %w[kdf mm2].include?(name) }
  unless entrypoints.length == 1 && entrypoints.first.last == marker.fetch('artifact_sha256') &&
         Digest::SHA256.hexdigest(JSON.generate(runtime_files)) == marker.fetch('runtime_set_sha256')
    raise 'The extracted macOS KDF library/runtime bytes do not match their verified artifact marker.'
  end

  header, status = Open3.capture2e('xcrun', 'otool', '-hv', library)
  raise 'The bundled KDF file is not a Mach-O dynamic library.' unless status.success? && header.match?(/\bDYLIB\b/)
  slices, status = Open3.capture2e('xcrun', 'lipo', '-archs', library)
  raise 'The bundled KDF library architectures could not be read.' unless status.success?
  requested = architectures.empty? ? slices.split : architectures
  unless !requested.empty? && requested.all? { |arch| %w[arm64 x86_64].include?(arch) && slices.split.include?(arch) }
    raise 'The verified KDF library does not contain every requested macOS architecture.'
  end
  requested.each do |arch|
    identity, status = Open3.capture2e('xcrun', 'otool', '-arch', arch, '-D', library)
    unless status.success? && identity.lines.map(&:strip).include?('@rpath/libkdflib.dylib')
      raise 'The KDF library install name must be @rpath/libkdflib.dylib for app-bundle loading.'
    end
    symbols, status = Open3.capture2e('xcrun', 'nm', '-arch', arch, '-gjU', library)
    unless status.success? && %w[_mm2_main _mm2_main_status _mm2_stop].all? { |symbol| symbols.lines.map(&:strip).include?(symbol) }
      raise 'The verified KDF library is missing a required wallet-engine export.'
    end
  end
  library
end

if $PROGRAM_NAME == __FILE__
  begin
    validate_native_kdf(ARGV.fetch(0))
    puts 'Verified native KDF library is ready for CocoaPods embedding.'
  rescue StandardError => error
    warn "error: #{error.message}"
    exit 1
  end
end
