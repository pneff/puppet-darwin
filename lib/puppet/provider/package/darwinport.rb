# darwinport provider currently broken, see
# http://projects.reductivelabs.com/issues/2331

require 'puppet/provider/package'

Puppet::Type.type(:package).provide :darwinport, :parent => Puppet::Provider::Package do
    desc "Package management using DarwinPorts on OS X."

    confine :operatingsystem => :darwin
    commands :port => "/opt/local/bin/port"

    def self.eachpkgashash
        # list out all of the packages
        open("| #{command(:port)} list installed") { |process|
            regex = %r{(\S+)\s+@(\S+)\s+(\S+)}
            fields = [:name, :ensure, :location]
            hash = {}

            # now turn each returned line into a package object
            process.each { |line|
                hash.clear

                if match = regex.match(line)
                    fields.zip(match.captures) { |field,value|
                        hash[field] = value
                    }

                    hash.delete :location
                    hash[:provider] = self.name
                    yield hash.dup
                else
                    raise Puppet::DevError,
                        "Failed to match dpkg line %s" % line
                end
            }
        }
    end

    def self.instances
        packages = []

        eachpkgashash do |hash|
            packages << new(hash)
        end

        return packages
    end

    def self.basename(name)
        # Returns the base name of the package (everything before the space)
        return name.split[0]
    end

    def install
        should = @resource.should(:ensure)

        # Seems like you can always say 'upgrade' not quite... 'install' seems
        # to be required before you can do 'upgrade'
        name = @resource[:name]
        # Split so we can install with options, e.g. `ports install git-core +svn`
        parts = name.split
        output = port "install", *parts
        if output =~ /^Error: No port/
            raise Puppet::ExecutionFailure, "Could not find package %s" % @resource[:name]
        end
    end

    def query
        version = nil
        self.class.eachpkgashash do |hash|
            if hash[:name] == self.class.basename(@resource[:name])
                return hash
            end
        end

        return nil
    end

    def latest
        # info = port :search, "^#{@resource[:name]}$"
        info = port :list, self.class.basename(@resource[:name])

        if $? != 0 or info =~ /^Error/
            return nil
        end

        ary = info.split(/\s+/)
        version = ary[1].sub(/^@/, '')  # versions are now the second in, not the third ins

        return version
    end

    def uninstall
        port :uninstall, self.class.basename(@resource[:name])
    end

    def update
        should = @resource.should(:ensure)
        
        # use 'upgrade' for update mode
        output = port "upgrade", self.class.basename(@resource[:name])
        if output =~ /^Error: No port/
            raise Puppet::ExecutionFailure, "Could not find package %s" % @resource[:name]
        end
    end
end
