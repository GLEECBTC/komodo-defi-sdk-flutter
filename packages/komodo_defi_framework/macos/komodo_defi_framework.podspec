has_static_library = File.exist?('Frameworks/libkdflib.a')
has_dynamic_library = File.exist?('lib/libkdflib.dylib')

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

  if has_dynamic_library
    s.resource_bundles = {
      'kdf_resources' => ['lib/*.dylib']
    }
  end

  if has_static_library
    s.vendored_libraries = ['Frameworks/libkdflib.a']
  end

  s.preserve_paths = ['bin/kdf', 'lib/libkdflib.dylib', 'Frameworks/libkdflib.a']

  s.script_phase = {
    :name => 'Install kdf executable and/or dylib',
    :execution_position => :before_compile,
    :script => <<-SCRIPT
      # Get the application support directory for macOS
      APP_SUPPORT_DIR="${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/Contents/Library/Application Support"
      FRAMEWORKS_DIR="${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/Contents/Frameworks"
      HELPERS_DIR="${TARGET_BUILD_DIR}/${CONTENTS_FOLDER_PATH}/Helpers"
      
      # Create all required directories in one go
      mkdir -p "$APP_SUPPORT_DIR" "$FRAMEWORKS_DIR" "$HELPERS_DIR"
      
      # Track if we found at least one of the required files
      FOUND_REQUIRED_FILE=0
  
      # Check if the kdf executable exists and copy it
      if [ -f "${PODS_TARGET_SRCROOT}/bin/kdf" ]; then
        echo "kdf executable found, copying..."
        cp "${PODS_TARGET_SRCROOT}/bin/kdf" "$APP_SUPPORT_DIR/kdf"
        chmod +x "$APP_SUPPORT_DIR/kdf"
        FOUND_REQUIRED_FILE=1
      else
        echo "Warning: kdf executable not found in bin/kdf"
      fi
      
      # Check if the dylib exists and copy it
      if [ -f "${PODS_TARGET_SRCROOT}/lib/libkdflib.dylib" ]; then
        echo "libkdflib.dylib found, copying..."
        cp "${PODS_TARGET_SRCROOT}/lib/libkdflib.dylib" "$FRAMEWORKS_DIR/libkdflib.dylib"
        install_name_tool -id "@rpath/libkdflib.dylib" "$FRAMEWORKS_DIR/libkdflib.dylib"
        FOUND_REQUIRED_FILE=1
      else
        echo "Warning: libkdflib.dylib not found in lib/libkdflib.dylib"
      fi

      if [ -f "${PODS_TARGET_SRCROOT}/Frameworks/libkdflib.a" ]; then
        echo "Static libkdflib.a found, linking through CocoaPods vendored_libraries"
        FOUND_REQUIRED_FILE=1
      else
        echo "Warning: libkdflib.a not found in Frameworks/libkdflib.a"
      fi
      
      # Prune binary slices to match $ARCHS (preserve universals) in Release builds only
      case "$CONFIGURATION" in
        Release*)
          TARGET_ARCHS="${ARCHS:-$(arch)}"

          thin_binary_to_archs() {
            file="$1"
            keep_archs="$2"

            [ -f "$file" ] || return 0

            # Only act on fat files (multi-arch)
            if ! lipo -info "$file" | grep -q 'Architectures in the fat file'; then
              return 0
            fi

            bin_archs="$(lipo -archs "$file" 2>/dev/null || true)"
            [ -n "$bin_archs" ] || return 0

            dir="$(dirname "$file")"
            base="$(basename "$file")"
            work="$file"

            for arch in $bin_archs; do
              echo "$keep_archs" | tr ' ' '\n' | grep -qx "$arch" && continue
              echo "Removing architecture $arch from $base"
              next="$(mktemp "$dir/.${base}.XXXXXX")"
              lipo "$work" -remove "$arch" -output "$next"
              [ "$work" != "$file" ] && rm -f "$work"
              work="$next"
            done

            if [ "$work" != "$file" ]; then
              mv -f "$work" "$file"
            fi
          }

          thin_binary_to_archs "$APP_SUPPORT_DIR/kdf" "$TARGET_ARCHS"
          if [ -f "$APP_SUPPORT_DIR/kdf" ]; then chmod +x "$APP_SUPPORT_DIR/kdf"; fi

          thin_binary_to_archs "$FRAMEWORKS_DIR/libkdflib.dylib" "$TARGET_ARCHS"
          if [ -f "$FRAMEWORKS_DIR/libkdflib.dylib" ]; then install_name_tool -id "@rpath/libkdflib.dylib" "$FRAMEWORKS_DIR/libkdflib.dylib"; fi
      esac

      # Signs a framework with the provided identity
      code_sign_if_enabled() {
        if [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" -a "${CODE_SIGNING_REQUIRED:-}" != "NO" -a "${CODE_SIGNING_ALLOWED}" != "NO" ]; then
          # Use the current code_sign_identity
          echo "Code Signing $1 with Identity ${EXPANDED_CODE_SIGN_IDENTITY_NAME}"
          local code_sign_cmd="/usr/bin/codesign --force --sign ${EXPANDED_CODE_SIGN_IDENTITY} ${OTHER_CODE_SIGN_FLAGS:-} --preserve-metadata=identifier,entitlements '$1'"

          if [ "${COCOAPODS_PARALLEL_CODE_SIGN}" == "true" ]; then
            code_sign_cmd="$code_sign_cmd &"
          fi
          echo "$code_sign_cmd"
          eval "$code_sign_cmd"
        else
          echo "Code Signing DISABLED. Is this correct for your configuration?"
        fi
      }

      # Resign the code if required by the build settings to avoid unstable apps
      code_sign_if_enabled "$APP_SUPPORT_DIR/kdf" || true
      # Helpers in komodo_defi_framework is now the ONLY place where KdfExecutableFinder.findExecutable() 
      # will look for the kdf binary on macOS. The APP_SUPPORT_DIR copy is redundant but kept for 
      # backward compatibility with older builds.
      if [ -f "$APP_SUPPORT_DIR/kdf" ]; then cp "$APP_SUPPORT_DIR/kdf" "$HELPERS_DIR/kdf"; fi
      code_sign_if_enabled "$FRAMEWORKS_DIR/libkdflib.dylib" || true

      # Static-library builds rely on vendored_libraries/force_load and
      # DynamicLibrary.process() at runtime, so there is nothing to copy/sign.
      if [ $FOUND_REQUIRED_FILE -eq 0 ]; then
        echo "Error: No compatible macOS KDF artefact was found."
        echo "Expected one of:"
        echo "  - bin/kdf"
        echo "  - lib/libkdflib.dylib"
        echo "  - Frameworks/libkdflib.a"
        exit 1
      fi
    SCRIPT
  }
  
  # Configuration for macOS build
  other_ldflags = if has_static_library
                    '-force_load $(PODS_TARGET_SRCROOT)/Frameworks/libkdflib.a -lstdc++ -framework SystemConfiguration'
                  else
                    '-framework SystemConfiguration'
                  end

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    # Allow building universal macOS apps (arm64 + x86_64). i386 remains excluded by default Xcode settings.
    'OTHER_LDFLAGS' => other_ldflags,
    # Add rpath to ensure dylib can be found at runtime when the dynamic artefact is used.
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
