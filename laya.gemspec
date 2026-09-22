require_relative "lib/laya/version"

Gem::Specification.new do |spec|
  spec.name = "laya"
  spec.version = Laya::VERSION
  spec.authors = ["Eduardo Hernandez"]
  spec.email = ["eduardoghdez.io@gmail.com"]

  spec.summary = "Run the Laya System-1 decision model from Ruby via ONNX Runtime"
  spec.description = "Typed decisions (choice, score, noul) with calibrated probabilities in one forward pass. " \
    "A Ruby port of @receptron/laya on top of the onnxruntime and tokenizers gems."
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*.rb", "exe/*", "README.md", "LICENSE.txt", "CHANGELOG.md"]
  spec.bindir = "exe"
  spec.executables = ["laya"]
  spec.require_paths = ["lib"]

  spec.add_dependency "onnxruntime", "~> 0.11"
  spec.add_dependency "tokenizers", "~> 0.7"
end
