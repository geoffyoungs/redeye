require 'rubygems'
gem 'rake-compiler'
require 'rake/extensiontask'
BASE_DIR = Dir.pwd
require 'rubygems/package_task'
require 'rake/testtask'

exts = []

namespace :prepare do
FileList["ext/*/*.cr"].each do |cr|
	dir = File.dirname(cr)
	name = File.basename(dir)
	desc "Generate source for #{name}"
	task(name.intern) do
		sh 'rubber-generate', '--build-dir', dir, cr
	end
end
end

spec = Gem::Specification.new do |s|
	s.name = "redeye"
	s.author = "Geoff Youngs"
	s.email = "git@intersect-uk.co.uk"
	s.version = "1.0.0"
	s.homepage = "http://github.com/geoffyoungs/redeye"
	s.summary = "Redeye correction for Gdk::Pixbuf"
	s.add_dependency("rubber-generate", ">= 0.0.17")
	s.add_dependency("glib2", ">= 1.1.9")
	s.add_dependency("gdk_pixbuf2", ">= 1.1.9")
	s.platform = Gem::Platform::RUBY
	s.extensions = FileList["ext/*/extconf.rb"]
	s.files = FileList['ext/*/*.{c,h,cr,rd}'] + ['Rakefile', 'README.md'] + FileList['lib/**/*.rb']
s.description = <<-EOF
Redeye correction methods for redeye
EOF
end
Gem::PackageTask.new(spec) do |pkg|
    pkg.need_tar = true
end
Rake::ExtensionTask.new("redeye", spec)

Rake::TestTask.new do |t|
	t.test_files = FileList['test/*_test.rb']
end

task :default, :compile

