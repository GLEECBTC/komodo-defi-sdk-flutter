require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require_relative '../../macos/validate_native_library'

# These are synthetic Mach-O fixtures, never wallet engines or release assets.
class MacosLibraryPackagingTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir('gleec-kdf-packaging-')
    @macos = File.join(@root, 'macos')
    @bin = File.join(@macos, 'bin')
    FileUtils.mkdir_p(@bin)
    FileUtils.mkdir_p(File.join(@root, 'app_build'))
    @library = File.join(@bin, 'libkdflib.dylib')
    File.write(File.join(@bin, 'kdf'), 'synthetic executable fixture')
    build_library
    @arch = Open3.capture2('xcrun', 'lipo', '-archs', @library).first.strip
    @manifest = {
      'api' => {
        'api_commit_hash' => 'f' * 40,
        'platforms' => {
          'macos' => {
            'matching_pattern' => '^kdf_[a-f0-9]{7,40}-mac-universal\\.zip$',
            'valid_zip_sha256_checksums' => ['a' * 64]
          }
        }
      }
    }
    @marker = {
      'api_commit_hash' => 'f' * 40,
      'checksums' => ['a' * 64],
      'archive_sha256' => 'a' * 64,
      'archive_filename' => "kdf_#{'f' * 40}-mac-universal.zip"
    }
    refresh_digests
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def build_library(include_stop: true)
    source = File.join(@root, 'fixture.c')
    File.write(source, "int mm2_main(void){return 0;}\nint mm2_main_status(void){return 0;}\n" +
      (include_stop ? "int mm2_stop(void){return 0;}\n" : ''))
    output, status = Open3.capture2e('xcrun', 'clang', '-dynamiclib', source,
      '-Wl,-install_name,@rpath/libkdflib.dylib', '-o', @library)
    raise output unless status.success?
  end

  def refresh_digests
    entries = %w[kdf libkdflib.dylib].map { |name| [name, Digest::SHA256.file(File.join(@bin, name)).hexdigest] }
    @marker['artifact_sha256'] = entries.first.last
    @marker['runtime_set_sha256'] = Digest::SHA256.hexdigest(JSON.generate(entries))
    persist
  end

  def persist
    File.write(File.join(@root, 'app_build', 'build_config.json'), JSON.generate(@manifest))
    File.write(File.join(@bin, '.api_last_updated_macos'), JSON.generate(@marker))
  end

  def validate
    validate_native_kdf(@macos, architectures: [@arch])
  end

  def test_accepts_matching_library_provenance_architecture_and_exports
    assert_equal @library, validate
  end

  def test_executable_only_archive_is_not_accepted
    File.delete(@library)
    assert_match(/executable-only/, assert_raises(RuntimeError) { validate }.message)
  end

  def test_stale_commit_is_not_accepted
    @marker['api_commit_hash'] = 'e' * 40
    persist
    assert_match(/provenance/, assert_raises(RuntimeError) { validate }.message)
  end

  def test_archive_outside_pinned_checksum_set_is_not_accepted
    @marker['archive_sha256'] = 'b' * 64
    persist
    assert_match(/provenance/, assert_raises(RuntimeError) { validate }.message)
  end

  def test_modified_library_bytes_are_not_accepted
    File.open(@library, 'ab') { |file| file.write('changed') }
    assert_match(/runtime bytes/, assert_raises(RuntimeError) { validate }.message)
  end

  def test_extra_stale_runtime_is_not_accepted
    File.write(File.join(@bin, 'libmm2.dylib'), 'old runtime')
    assert_match(/runtime bytes/, assert_raises(RuntimeError) { validate }.message)
  end

  def test_symbolic_link_is_not_accepted
    target = File.join(@root, 'outside.dylib')
    FileUtils.mv(@library, target)
    File.symlink(target, @library)
    assert_match(/Missing verified/, assert_raises(RuntimeError) { validate }.message)
  end

  def test_static_archive_or_executable_disguised_as_dylib_is_not_accepted
    File.write(@library, 'not a dynamic library')
    refresh_digests
    assert_match(/Mach-O dynamic/, assert_raises(RuntimeError) { validate }.message)
  end

  def test_missing_engine_export_is_not_accepted
    build_library(include_stop: false)
    refresh_digests
    assert_match(/required wallet-engine export/, assert_raises(RuntimeError) { validate }.message)
  end

  def test_nonportable_install_name_is_not_accepted
    _, status = Open3.capture2e('xcrun', 'install_name_tool', '-id', '/unavailable/build/libkdflib.dylib', @library)
    assert status.success?
    refresh_digests
    assert_match(/install name/, assert_raises(RuntimeError) { validate }.message)
  end

  def test_missing_architecture_is_not_accepted
    other = @arch == 'arm64' ? 'x86_64' : 'arm64'
    error = assert_raises(RuntimeError) { validate_native_kdf(@macos, architectures: [@arch, other]) }
    assert_match(/every requested macOS architecture/, error.message)
  end
end
