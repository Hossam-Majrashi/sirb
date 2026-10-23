#!/usr/bin/env ruby
# Hermetic podspec ABI configuration test; no CocoaPods/macOS/CEF binary needed.
require 'json'
require 'open3'
require 'rbconfig'
require 'set'
require_relative '../third_party/webview_cef/macos/embed_cef_helpers'

podspec = File.expand_path('../third_party/webview_cef/macos/webview_cef.podspec', __dir__)
# Model only the Pod::Spec DSL setters used by this path pod. Never execute its
# prepare_command. Capture the target flags Ruby evaluates for each wrapper type.
stub = <<~'RUBY'
  require 'json'
  module Pod
    class Spec
      attr_accessor :pod_target_xcconfig
      def self.new
        spec = allocate
        yield spec
        $captured = spec
      end
      def method_missing(*)
        nil
      end
    end
  end
  load ARGV.fetch(0)
  puts JSON.generate($captured.pod_target_xcconfig)
RUBY
%w[Debug Release RelWithDebInfo MinSizeRel].each do |type|
  env = { 'CEF_WRAPPER_BUILD_TYPE' => type, 'WEBVIEW_CEF_MACOS_ARCH' => 'universal' }
  stdout, stderr, status = Open3.capture3(env, RbConfig.ruby, '-e', stub, podspec)
  raise "Podspec failed for #{type}: #{stderr}" unless status.success?
  flags = JSON.parse(stdout).fetch('GCC_PREPROCESSOR_DEFINITIONS').split
  expected = type != 'Debug'
  raise "CEF NDEBUG ABI mismatch for #{type}: #{flags}" unless flags.include?('NDEBUG=1') == expected
  raise 'Missing GPU texture flag' unless flags.include?('WEBVIEW_CEF_GPU_TEXTURE=1')
end
_, _, status = Open3.capture3({ 'CEF_WRAPPER_BUILD_TYPE' => 'Unknown', 'WEBVIEW_CEF_MACOS_ARCH' => 'universal' }, RbConfig.ruby, '-e', stub, podspec)
raise 'Invalid wrapper configuration was accepted' if status.success?
# Exercise the structured Xcodeproj linker sets without CocoaPods/macOS. Keep
# unrelated frameworks/libraries/-ObjC and inherited flags, and remain idempotent.
flags = {
  frameworks: Set['Chromium', 'FlutterMacOS', 'Metal'],
  simple: Set['$(inherited)', '-ObjC', 'Embedded', 'Framework'],
  libraries: Set['c++', 'cef_dll_wrapper'], weak_frameworks: Set['GameController'],
  arg_files: Set['/tmp/list'], force_load: Set['/tmp/plugin.a']
}
config = Struct.new(:other_linker_flags).new(flags)
expected = Marshal.load(Marshal.dump(flags))
expected[:frameworks].delete('Chromium')
expected[:frameworks] << 'Chromium Embedded Framework'
expected[:simple].subtract(%w[Embedded Framework])
raise 'Broken CEF flags not repaired' unless WebviewCEF.repair_framework_link_flags(config)
raise 'Unrelated flags were changed' unless flags == expected
raise 'Repair was not idempotent' if WebviewCEF.repair_framework_link_flags(config)
grouped = { frameworks: Set['Chromium'], simple: Set['-ObjC', 'Embedded Framework'] }
raise 'Grouped orphan fragment was not repaired' unless WebviewCEF.repair_framework_link_flags(Struct.new(:other_linker_flags).new(grouped))
raise 'Grouped repair removed other flags' unless grouped == { frameworks: Set['Chromium Embedded Framework'], simple: Set['-ObjC'] }
genuine = { frameworks: Set['Chromium'], simple: Set['-ObjC'] }
raise 'Non-CEF Chromium framework was changed' if WebviewCEF.repair_framework_link_flags(Struct.new(:other_linker_flags).new(genuine))
raise 'Non-CEF flags mutated' unless genuine == { frameworks: Set['Chromium'], simple: Set['-ObjC'] }
puts 'PASS: four wrapper NDEBUG configurations, invalid-type rejection and targeted/idempotent CEF linker quoting'
