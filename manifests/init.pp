class darwin {
    darwin::defaults {
      "disable_autologin":
        domain => "/Library/Preferences/com.apple.loginwindow",
        key => "autoLoginUser",
        ensure => absent;

      "enable_firewall":
        domain => "/Library/Preferences/com.apple.alf",
        key => "globalstate",
        ensure => "1";

      # Don't write .DS_Store files on network devices.
      # http://www.macosxhints.com/article.php?story=20051130083652119
      "disable_ds_files":
        domain => "/Library/Preferences/com.apple.desktopservices",
        key => "DSDontWriteNetworkStores",
        ensure => "true";
    }

    modules_dir { "darwin": }
    modules_file {
      "darwin/accept.exp":
        source => "puppet:///darwin/accept.exp",
        group => 0;
    }
}

# Manages defaults on OSX.
# 
# $ensure can have the following values:
#    - absent: Make sure the domain/key pair is not around
#    - anything else: Set the value of the domain/key part to the given value
#
# The name variable is currently ignored.
define darwin::defaults($ensure, $domain, $key) {
    if $ensure == absent {
        exec { "defaults_remove_${domain}_${key}":
            command => "/usr/bin/defaults delete ${domain} ${key}",
            unless => "/usr/bin/defaults read ${domain} ${key} 2>&1 | grep -q 'does not exist'"
        }
    } else {
        exec { "defaults_set_${domain}_${key}":
            command => "/usr/bin/defaults write ${domain} ${key} '${ensure}'",
            unless => "/usr/bin/defaults read ${domain} ${key} | grep -q '^${ensure}$'"
        }
    }
}
