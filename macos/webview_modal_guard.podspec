Pod::Spec.new do |s|
  s.name = 'webview_modal_guard'
  s.version = '0.1.0'
  s.summary = 'Native input isolation for Flutter modals over macOS WebViews.'
  s.description = 'Window-scoped AppKit input routing while an explicit modal lease is active.'
  # Replace with the repository URL after the owner publishes the package.
  s.homepage = 'https://example.invalid/webview_modal_guard'
  s.license = { :type => 'Proprietary', :file => '../LICENSE' }
  s.author = 'WebView Modal Guard contributors'
  s.source = { :path => '.' }
  s.source_files = 'webview_modal_guard/Sources/webview_modal_guard/**/*.swift'
  s.resource_bundles = { 'webview_modal_guard_privacy' => ['webview_modal_guard/Sources/webview_modal_guard/PrivacyInfo.xcprivacy'] }
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '10.15'
  s.swift_version = '5.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
