Pod::Spec.new do |s|
  s.name = 'GotifyGeneratedClient'
  s.ios.deployment_target = '13.0'
  s.osx.deployment_target = '10.15'
  s.tvos.deployment_target = '13.0'
  s.watchos.deployment_target = '6.0'
  s.version = '2.1.0'
  s.source = { :git => 'git@github.com:OpenAPITools/openapi-generator.git', :tag => 'v2.1.0' }
  s.authors = 'OpenAPI Generator'
  s.license = 'MIT'
  s.homepage = 'https://github.com/OpenAPITools/openapi-generator'
  s.summary = 'GotifyGeneratedClient Swift SDK'
  s.source_files = 'Sources/GotifyGeneratedClient/**/*.swift'
  s.dependency 'Alamofire', '~> 5.10'
end
