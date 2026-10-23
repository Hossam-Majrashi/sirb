# webview_cef — macOS multi-process helper installer.
#
# Call from your macOS Podfile's post_install hook to make CEF run multi-process.
# It adds an "Embed CEF Helpers" run-script build phase to your app (Runner)
# target; that phase clones the prebuilt CEF helper into the five sub-process
# .app bundles inside your app's Frameworks dir on every build. No manual Xcode
# changes are required.
#
#   post_install do |installer|
#     installer.pods_project.targets.each do |target|
#       flutter_additional_macos_build_settings(target)
#     end
#     require File.expand_path(
#       'Flutter/ephemeral/.symlinks/plugins/webview_cef/macos/embed_cef_helpers.rb', __dir__)
#     WebviewCEF.install_helper_phase(installer)
#   end
#
# Without this hook the plugin still works, but falls back to single-process.
module WebviewCEF
  PHASE_NAME = 'Embed CEF Helpers'.freeze
  SCRIPT = 'bash "${SRCROOT}/Flutter/ephemeral/.symlinks/plugins/webview_cef/macos/scripts/embed_cef_helpers.sh"'.freeze

  # CocoaPods/Xcodeproj can split the vendored framework's spaced name while
  # merging aggregate flags (CocoaPods #11493). Repair only that exact three-
  # fragment signature, not all OTHER_LDFLAGS: other plugins need their flags.
  # Keep CEF's real bundle/install name; renaming it breaks dyld at launch.
  def self.repair_framework_link_flags(config)
    flags = config.other_linker_flags
    frameworks, simple = flags[:frameworks], flags[:simple]
    fragments = simple.include?('Embedded') && simple.include?('Framework')
    fragments ||= simple.include?('Embedded Framework')
    return false unless frameworks.include?('Chromium') && fragments

    frameworks.delete('Chromium')
    frameworks << 'Chromium Embedded Framework'
    simple.delete('Embedded')
    simple.delete('Framework')
    simple.delete('Embedded Framework')
    true
  end

  def self.install_helper_phase(installer)
    installer.aggregate_targets.each do |aggregate|
      project = aggregate.user_project
      next unless project

      aggregate.xcconfigs.each do |configuration, config|
        next unless repair_framework_link_flags(config)

        path = aggregate.xcconfig_path(configuration)
        config.save_as(path)
        puts "webview_cef: repaired CEF framework quoting in '#{path}'."
      end

      aggregate.user_targets.each do |target|
        # Only application targets get a bundle to embed helpers into.
        next unless target.product_type == 'com.apple.product-type.application'

        # Idempotent: remove a previous phase before re-adding. Use
        # remove_from_project (not delete_if) so the underlying
        # PBXShellScriptBuildPhase object is deleted from the project graph, not
        # just detached from buildPhases — otherwise every `pod install` (Flutter
        # runs it routinely) leaves an orphaned phase object behind and the
        # tracked project.pbxproj grows unboundedly.
        target.build_phases
              .select { |ph| ph.respond_to?(:name) && ph.name == PHASE_NAME }
              .each(&:remove_from_project)

        phase = target.new_shell_script_build_phase(PHASE_NAME)
        phase.shell_path = '/bin/bash'
        phase.shell_script = SCRIPT
        # Runs every build; cloning is cheap and keeps helpers in sync.
        phase.always_out_of_date = '1' if phase.respond_to?(:always_out_of_date=)
        puts "webview_cef: added '#{PHASE_NAME}' phase to target '#{target.name}'."
      end

      project.save
    end
  end
end
