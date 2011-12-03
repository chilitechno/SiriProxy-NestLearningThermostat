# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)

Gem::Specification.new do |s|
  s.name        = "siriproxy-nestlearningthermostat"
  s.version     = "0.0.1" 
  s.authors     = ["chilitechno"]
  s.email       = [""]
  s.homepage    = ""
  s.summary     = %q{A thermostat plugin for SiriProxy that controls a Nest Learning thermostat}
  s.description = %q{Sniffing of iphone app traffic}

  s.rubyforge_project = "siriproxy-nestlearningthermostat"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  # specify any dependencies here; for example:
  # s.add_development_dependency "rspec"
  s.add_runtime_dependency "json"
  s.add_runtime_dependency "httparty"
end
