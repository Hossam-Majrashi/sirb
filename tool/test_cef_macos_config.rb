#!/usr/bin/env ruby
# Hermetic podspec ABI configuration test; no CocoaPods/macOS/CEF binary needed.
require 'json'
require 'open3'
require 'rbconfig'

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
puts 'PASS: four CEF wrapper configurations match pod NDEBUG flags; unknown types rejected'
