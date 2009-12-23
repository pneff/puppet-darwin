#
# pkgzip.rb
#
# Install Installer.app packages wrapped up inside a ZIP file.
#
# Copied from appdmg by Patrice Neff.

require 'puppet/provider/package'
require 'facter/util/plist'

Puppet::Type.type(:package).provide :pkgzip, :parent => Puppet::Provider::Package do
    desc "Package management based on Apple's Installer.app and DiskUtility.app.  This package works by checking the contents of a DMG image for Apple pkg or mpkg files. Any number of pkg or mpkg files may exist in the root directory of the DMG file system. Sub directories are not checked for packages.  See `the wiki docs </trac/puppet/wiki/DmgPackages>` for more detail."

    confine :operatingsystem => :darwin
    commands :installer => "/usr/sbin/installer"
    commands :hdiutil => "/usr/bin/hdiutil"
    commands :curl => "/usr/bin/curl"
    commands :unzip => "/usr/bin/unzip"

    # JJM We store a cookie for each installed .pkg.zip in /var/db
    def self.instance_by_name
        Dir.entries("/var/db").find_all { |f|
            f =~ /^\.puppet_pkgzip_installed_/
        }.collect do |f|
            name = f.sub(/^\.puppet_pkgzip_installed_/, '')
            yield name if block_given?
            name
        end
    end

    def self.instances
        instance_by_name.collect do |name|
            new(
                :name => name,
                :provider => :pkgzip,
                :ensure => :installed
            )
        end
    end

    def self.extract(file, dir, extract_type)
        files = []
        if extract_type == :zip
            lines = unzip file, '-d', dir
            for line in lines
                file = line.split(':', 2)[1]
                if not file.nil?
                    files.push(file.strip)
                end
            end
        elsif extract_type == :targz
            lines = tar '-xvf', file, '-C', dir
            for line in lines
                if line[0..0] != '.' # Not interested in hidden files
                    # Line layout: "x relative name"
                    files.push(dir + line.strip[2..-1])
                end
            end
        end
        return files
    end

    def self.installpkg(source, name, orig_source)
      installer "-pkg", source, "-target", "/"
      # Non-zero exit status will throw an exception.
      File.open("/var/db/.puppet_pkgzip_installed_#{name}", "w") do |t|
          t.print "name: '#{name}'\n"
          t.print "source: '#{orig_source}'\n"
      end
    end

    def self.installpkgzip(source, name)
        extract_type = nil
        if source =~ /\.zip$/i
            extract_type = :zip
        elsif source =~ /\.tar\.gz$/i
            extract_type = :targz
        elsif source =~ /\.tbz$/i
            extract_type = :targz
        elsif source =~ /\.pkg$/i
            extract_type = :none
        else
            self.fail "Source must end in .zip"
        end

        require 'open-uri'
        cached_source = source
        if %r{\A[A-Za-z][A-Za-z0-9+\-\.]*://} =~ cached_source
            cached_source = "/tmp/#{name}"
            begin
                curl "-o", cached_source, "-C", "-", "-k", "-s", "--url", source
                Puppet.debug "Success: curl transfered [#{name}]"
            rescue Puppet::ExecutionFailure
                Puppet.debug "curl did not transfer [#{name}].  Falling back to slower open-uri transfer methods."
                cached_source = source
            end
        end

        begin
            Dir.mktmpdir do |dir|
                dir += '/' unless dir[-1..-1] == '/'
                if extract_type == :none
                    files = [cached_source]
                else
                    files = extract cached_source, dir, extract_type
                end
                files.each do |file|
                    relfile = file[dir.length..-1]
                    if not relfile.nil? and relfile.chomp('/') =~ /\.m{0,1}pkg$/i
                        installpkg(file, name, source)
                    end
                end
            end
        ensure
            # JJM Remove the file if open-uri didn't already do so.
            File.unlink(cached_source) if File.exist?(cached_source)
        end # begin
    end

    def query
        if FileTest.exists?("/var/db/.puppet_pkgzip_installed_#{@resource[:name]}")
            return {:name => @resource[:name], :ensure => :present}
        else
            return nil
        end
    end

    def install
        source = nil
        unless source = @resource[:source]
            raise Puppet::Error.new("Mac OS X PKG DMG's must specify a package source.")
        end
        unless name = @resource[:name]
            raise Puppet::Error.new("Mac OS X PKG DMG's must specify a package name.")
        end
        self.class.installpkgzip(source,name)
    end
end

