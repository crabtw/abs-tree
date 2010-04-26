#!/usr/bin/ruby

require 'date'
require 'digest/md5'
require 'erb'
require 'fileutils'
require 'rubygems'
require 'tmpdir'

PKGBUILD = %{# Generated by gem2arch
# Contributor: <%= contact %>

_gemname=<%= gem_name %>
pkgname=ruby-$_gemname
pkgver=<%= gem_ver %>
pkgrel=1
pkgdesc="<%= description %>"
arch=('i686' 'x86_64')
url="<%= website %>"
license=('')
depends=('ruby'<%= depends %>)
makedepends=('rubygems')
source=(http://gems.rubyforge.org/gems/$_gemname-$pkgver.gem)
noextract=($_gemname-$pkgver.gem)
md5sums=('<%= md5sum %>')

build() {
  cd $srcdir
  local _gemdir="$(ruby -e'puts Gem.default_dir')"
  gem install --ignore-dependencies -i "$pkgdir$_gemdir" $_gemname-$pkgver.gem
}
}

def download(gem_name, gem_ver = nil)
  version = gem_ver || Gem::Requirement.default

  all = Gem::Requirement.default
  dep = Gem::Dependency.new gem_name, version

  puts "Fetch #{gem_name} spec"

  specs_and_sources = Gem::SpecFetcher.fetcher.fetch dep, all
  specs_and_sources.sort_by { |spec,| spec.version }
  spec, source_uri = specs_and_sources.last

  if spec.nil? then
    $stderr.puts "Could not find #{gem_name} in any repository"
    exit 1
  end

  puts "Downloaded #{spec.full_name}"

  path = Gem::RemoteFetcher.fetcher.download spec, source_uri
  FileUtils.mv path, "#{spec.full_name}.gem"

  return spec
end

def calc_digest(file_name)
  md5sum = Digest::MD5.new
  file_size = File.size file_name

  File.open(file_name) do |f|
    while buf = f.read(1024)
      md5sum << buf
    end
  end

  return md5sum.to_s
end

def gen_pkgbuild(spec)
  gem_name = spec.name
  gem_ver = spec.version

  contact = ENV['ARCH_RUBY'] || ''

  if contact.empty?
    puts
    puts "Warning: ARCH_RUBY environment variable not set."
    puts "Set this to the maintainer contact you wish to use."
    puts "E.g. 'Arch Ruby Team <arch-ruby@archlinux.org>'"
    puts
  end

  website = spec.homepage
  description = spec.summary

  md5sum = calc_digest(spec.full_name + '.gem')

  depends = spec.runtime_dependencies
  depends = if depends.empty? then ""
  else
    ' ' + depends.map do |d|
      d.requirement.requirements.map do |comp, ver|
        comp = '>=' if comp == '~>'
        "'ruby-#{d.name}#{comp}#{ver}'"
      end
    end.join(" ")
  end

  return ERB.new(PKGBUILD).result(binding)
end

if $0 == __FILE__
  if ARGV.length < 1
    puts "Usage: #{$0} GEM_NAME [GEM_VER]"
    exit
  end

  Dir.mktmpdir do |tmp_dir|
    base_dir = Dir.pwd
    Dir.chdir tmp_dir

    spec = download *ARGV.take(2)

    target_dir = "#{base_dir}/ruby-#{spec.name}"
    Dir.mkdir target_dir unless File.exist? target_dir

    {
      'PKGBUILD' => lambda {|s| gen_pkgbuild s }
    }.each do |file, gen_file|
      puts "Generate #{file} for ruby-#{spec.full_name}"
      File.open(file, 'w') {|f| f.write gen_file.call(spec) }

      FileUtils.mv file, target_dir
    end

    Dir.chdir base_dir
  end
end
