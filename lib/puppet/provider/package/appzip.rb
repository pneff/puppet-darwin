# Patrice Neff <software@patrice.ch>
# Mac OS X Package Installer which handles application (.app)
# bundles inside a ZIP file.
#
# Most of the code copied from the appdmg provider. It might even be a good
# idea to merge those two.

require 'puppet/provider/package'

Puppet::Type.type(:package).provide(:appzip, :parent => Puppet::Provider::Package) do
    desc "Package management which copies application bundles to a target."

    confine :operatingsystem => :darwin

    commands :unzip => "/usr/bin/unzip"
    commands :tar => "/usr/bin/tar"
    commands :curl => "/usr/bin/curl"
    commands :ditto => "/usr/bin/ditto"

    # JJM We store a cookie for each installed .app in /var/db
    def self.instances_by_name
        Dir.entries("/var/db").find_all { |f|
            f =~ /^\.puppet_appzip_installed_/
        }.collect do |f|
            name = f.sub(/^\.puppet_appzip_installed_/, '')
            yield name if block_given?
            name
        end
    end

    def self.instances
        instances_by_name.collect do |name|
            new(:name => name, :provider => :appzip, :ensure => :installed)
        end
    end

    def self.installapp(source, name, orig_source)
      appname = File.basename(source)
      return if appname[0..0] == '.' # Can happen due to metadata files in targz files
      ditto "--rsrc", source, "/Applications/#{appname}"
      File.open("/var/db/.puppet_appzip_installed_#{name}", "w") do |t|
          t.print "name: '#{name}'\n"
          t.print "source: '#{orig_source}'\n"
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

    def self.installpkg(source, name)
        extract_type = nil
        if source =~ /\.zip$/i
            extract_type = :zip
        elsif source =~ /\.tar\.gz$/i
            extract_type = :targz
        elsif source =~ /\.tbz$/i
            extract_type = :targz
        else
            self.fail "Source must end in .zip"
        end

        require 'open-uri'
        cached_source = source
        if %r{\A[A-Za-z][A-Za-z0-9+\-\.]*://} =~ cached_source
            cached_source = "/tmp/#{name}"
            curl "-o", cached_source, "-L", "-C", "-", "-k", "-s", "--url", source
            Puppet.debug "Success: curl transfered [#{name}]"
        end

        begin
            Dir.mktmpdir do |dir|
                dir += '/' unless dir[-1..-1] == '/'
                files = extract cached_source, dir, extract_type
                files.each do |file|
                    relfile = file[dir.length..-1]
                    if not relfile.nil? and relfile.chomp('/')[-4..-1] == '.app'
                        if relfile.scan("\.app").size == 1 # Avoids .app within .app
                            installapp(file, name, source)
                        end
                    end
                end
            end
        ensure
            # JJM Remove the file if open-uri didn't already do so.
            File.unlink(cached_source) if File.exist?(cached_source)
        end # begin
    end # def self.installpkg

    def query
        if FileTest.exists?("/var/db/.puppet_appzip_installed_#{@resource[:name]}")
            return {:name => @resource[:name], :ensure => :present}
        else
            return nil
        end
    end

    def install
        source = nil
        unless source = @resource[:source]
            self.fail "Mac OS X PKG DMG's must specify a package source."
        end
        unless name = @resource[:name]
            self.fail "Mac OS X PKG DMG's must specify a package name."
        end
        self.class.installpkg(source,name)
    end
end
