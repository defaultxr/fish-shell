function __fish_print_hostnames -d "Print a list of known hostnames"
    # Print all hosts from /etc/hosts. Use 'getent hosts' on OSes that support it
    # (OpenBSD and Cygwin do not).
    #
    # Test if 'getent hosts' works and redirect output so errors don't print.
    if type -q getent
        and getent hosts >/dev/null 2>&1
        # Ignore zero IPs.
        getent hosts | string match -r -v '^0.0.0.0' | string replace -r '^\s*\S+\s+' '' | string split ' '
    else if test -r /etc/hosts
        # Ignore commented lines and functionally empty lines.
        string match -r -v '^\s*0.0.0.0|^\s*#|^\s*$' </etc/hosts | string replace -r -a '#.*$' '' | string replace -r '^\s*\S+\s+' '' | string trim | string replace -r -a '\s+' ' ' | string split ' '
    end

    # Print nfs servers from /etc/fstab
    if test -r /etc/fstab
        string match -r '^\s*[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3]:|^[a-zA-Z\.]*:' </etc/fstab | string replace -r ':.*' ''
    end

    # Check hosts known to ssh.
    # Yes, seriously - the default specifies both with and without "2".
    set -l known_hosts ~/.ssh/known_hosts{,2} /etc/ssh/{,ssh_}known_hosts{,2}
    # Check default ssh configs.
    set -l ssh_config
    # Get alias and commandline options.
    set -l ssh_func_tokens (functions ssh | string match '*command ssh *' | string split ' ')
    set -l ssh_command $ssh_func_tokens (commandline -cpo)
    # Extract ssh config path from last -F short option.
    if contains -- '-F' $ssh_command
        set -l ssh_config_path_is_next 1
        for token in $ssh_command
            if contains -- '-F' $token
                set ssh_config_path_is_next 0
            else if test $ssh_config_path_is_next -eq 0
                set ssh_config (eval "echo $token")
                set ssh_config_path_is_next 1
            end
        end
    else
        set ssh_config $ssh_config ~/.ssh/config
    end

    # Extract ssh config paths from Include option
    function _ssh_include --argument-names ssh_config
        # Relative paths in Include directive use /etc/ssh or ~/.ssh depending on
        # system or user level config. -F will not override this behaviour
        set -l relative_path $HOME/.ssh
        if string match '/etc/ssh/*' -- $ssh_config
            set relative_path '/etc/ssh'
        end

        function _recursive --no-scope-shadowing
            set -l orig_dir $PWD
            set -l paths
            for config in $argv
                set -a paths (cat $config ^/dev/null \
                # Keep only Include lines
                | string match -r -i '^\s*Include\s+.+' \
                # Remove Include syntax
                | string replace -r -i '^\s*Include\s+' '' \
                # Normalize whitespace
                | string trim | string replace -r -a '\s+' ' ')
            end

            builtin cd $relative_path
            set -l new_paths
            for path in $paths
                set -l expanded_path
                eval "set expanded_path (printf \"%s\n\" $path)"
                for path in $expanded_path
                    # Resolve "relative" paths in accordance to ssh path resolution
                    if string match -qv '/*' $path
                        set path $relative_path/$path
                    end
                    echo $path
                    set new_paths $new_paths $path
                end
            end
            builtin cd $orig_dir

            if test -n "$new_paths"
                _recursive $new_paths
            end
        end
        _recursive $ssh_config
    end
    set -l ssh_configs /etc/ssh/ssh_config (_ssh_include /etc/ssh/ssh_config) $ssh_config (_ssh_include $ssh_config)

    for file in $ssh_configs
        if test -r $file
            # Print hosts from system wide ssh configuration file
            string match -r -i '^\s*Host\s+\S+' <$file | string replace -r -i '^\s*Host\s+' '' | string trim | string replace -r '\s+' ' ' | string split ' ' | string match -v '*\**'
            # Extract known_host paths.
            set -a known_hosts (string match -ri '^\s*UserKnownHostsFile|^\s*GlobalKnownHostsFile' <$file | string replace -ri '.*KnownHostsFile\s*' '')
        end
    end
    for file in $known_hosts
        # Ignore hosts that are hashed, commented or have custom ports (like [localhost]:2200)
        test -r $file
        and string replace -ra '(\S+) .*' '$1' <$file | string match -r '^[^#|[=]+$' | string split ","
    end
    return 0
end
