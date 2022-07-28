prsync__profiles_path=".prsync-profiles"
prsync__log_path="$HOME/tmp"

# To be used by profiles
function prsync__get_remote_env {
    local remote_env_var="$1"
    local remote_env_val

    # Warning: 'local' counts as a command for the purposes of $?,
    #          whereas pure variable assignment does not.
    local err="error: remote must be specified in the profile config to use \`prsync__get_remote_env\`"
    remote_env_val="$(ssh ${prsync__remote_port:+-p "$prsync__remote_port"} "${prsync__remote:?$err}" "env | grep '^$remote_env_var=' | sed 's/^$remote_env_var=//'")"

    local result="$?"
    printf '%s' "$remote_env_val"
    return "$result"
}

# To be used by profiles
# Also used below to fetch files from the remote profile, if there is one
function prsync__get_remote_files_raw {
    scp -q ${prsync__remote_port:+-P "$prsync__remote_port"} "$@"
    return $?
}

# To be used by profiles
function prsync__get_remote_files {
    # Extract first to second-last parameters (edited from https://stackoverflow.com/a/44939917)
    # Notes:
    # - slicing an array: https://stackoverflow.com/a/1336245
    # - slicing the positional parameter arrays ($* and $@) does not require @-indexing the array (from a comment on the above)
    # - experimentation: when run, "${@::N}" (where N is some number) returns 'bash' as the first param - exclude it
    local all_but_last=("${@:1:${#@}-1}")

    local err="error: remote must be specified in the profile config to use \`prsync__get_remote_env\`"

    # Prefix "$prsync__remote:" to all elements in all_but_last (edited from https://stackoverflow.com/a/12744170)
    # Get last parameter (https://stackoverflow.com/a/9970224)
    prsync__get_remote_files_raw "${all_but_last[@]/#/${prsync__remote:?$err}:}" "${!#}"
    return $?
}

# Reset all variables that can be set in a prsync profile to *blank*
function prsync__unset_profile_vars {
    unset prsync__remote
    unset prsync__remote_port

    unset prsync__dir1
    unset prsync__dir2
    unset prsync__remote_dir1
    unset prsync__remote_dir2

    unset prsync__options
}

# # 'profile rsync'
function prsync {
    # The following is a modified version of this: http://stackoverflow.com/a/246128
    local prsync_source
    local prsync_dir

    prsync_source="${BASH_SOURCE[0]}"

    # resolve $prsync_source until the file is no longer a symlink
    while [ -h "$prsync_source" ]; do
        prsync_dir="$(cd -P "$( dirname "$prsync_source" )" && pwd)"
        prsync_source="$(readlink "$prsync_source")"

        # if $prsync_source was a relative symlink, we need to resolve it relative to the path where the symlink file was located
        [[ $prsync_source != /* ]] && prsync_source="$prsync_dir/$prsync_source"
    done
    prsync_dir="$(cd -P "$( dirname "$prsync_source" )" && pwd)"

    # ------------------------------------------------------------

    # Used throughout to store error messages for unset/null parameter expansion
    local err

    # Options
    local help=false
    local write_=false # Do not write by default (`rsync -n` is default)

    if [ "$(printf '%s' "$1" | head -c 1)" = '-' ]; then
        case "$1" in
            '-h' | '-?' | '--help') help=true; shift;;
            '-w' | '--write') write_=true; shift;;
            *)
                printf "unrecognised option: '%s'\n" "$1"
                return 1;;
        esac
    fi

    if [ "$help" = true ]; then
        cat "$prsync_dir/help/prsync.help.txt"
        return 0
    fi

    # Get positional params: sync direction, profile to use
    local direction
    local profile

    if [ "$1" = '' ]; then
        printf 'error: no direction given\n'
        return 1
    else
        case "$1" in
            'to' | 'from') direction="$1";;
            *)
                printf "unrecognised value for 'direction' parameter: '%s'" "$1"
                return 1
                ;;
        esac
        shift
    fi

    if [ "$1" = '' ]; then
        printf 'error: no profile given\n'
        return 1
    else
        profile="$1"
        shift
    fi

    # Load profile from your home profiles (which may or may not be your
    # dir1's or dir2's profiles)
    prsync__unset_profile_vars
    . "$HOME/$prsync__profiles_path/$profile/profile"

    # Verify the configuration and extract variables
    local src dest
    local src_copy dest_copy

    # Note: It's better to check for direction inside remote than to
    #       check for remote inside direction for storing the copy
    #       command, as this avoids double-checking the 'neither is
    #       remote' case and keeps the 'remote-ness' of the src/dest
    #       together with the command to use them. However, it
    #       duplicates the logic of which directory (dir1/dir2) becomes
    #       src/dest. Both require double-checking the inner case
    #       (whether $direction or $prsync__remote_dirN).

    if [ "$prsync__remote_dir1" != '' -a "$prsync__remote_dir2" != '' ]; then
        # Both dir1 and dir2 being remote is an error - rsync can't do that
        printf '%s\n' "error: src and dest cannot both be remote"
        return 1
    elif [ "$prsync__remote_dir1" != '' ]; then
        err="error: remote must be specified in the profile config, as dir1 is remote"
        dir1="${prsync__remote:?$err}:$prsync__remote_dir1"

        err="error: dir2 must be specified in the profile config and not be remote, as dir1 is remote"
        dir2="${prsync__dir2:?$err}"

        case "$direction" in
            'to') src_copy="prsync__get_remote_files_raw" && dest_copy="cp";;
            'from') src_copy="cp" && dest_copy="prsync__get_remote_files_raw";;
        esac
    elif [ "$prsync__remote_dir2" != '' ]; then
        err="error: dir1 must be specified in the profile config and not be remote, as dir2 is remote"
        dir1="${prsync__dir1:?$err}"

        err="error: remote must be specified in the profile config, as dir1 is remote"
        dir2="${prsync__remote:?$err}:$prsync__remote_dir2"

        case "$direction" in
            'to') src_copy="cp" && dest_copy="prsync__get_remote_files_raw";;
            'from') src_copy="prsync__get_remote_files_raw" && dest_copy="cp";;
        esac
    else
        err="error: dir1 must be specified in the profile config"
        dir1="${prsync__dir1:?$err}"

        err="error: dir2 must be specified in the profile config"
        dir2="${prsync__dir2:?$err}"

        src_copy="cp" && dest_copy="cp"
    fi

    if [ "$direction" = 'to' ]; then
        src="$dir1" && dest="$dir2"
    else
        src="$dir2" && dest="$dir1"
    fi

    # Retrieve src and dest rsync include/exclude files from their respective profiles
    local collated_profile_path="$HOME/$prsync__profiles_path/$profile/collated-profile"

    test ! -d "$collated_profile_path" &&
        mkdir "$collated_profile_path" ||
        rm "$collated_profile_path"/*

    $src_copy "$src/$prsync__profiles_path/$profile/include" "$collated_profile_path/src-include" 2>/dev/null
    if [ $? != 0 ]; then
        find "$src" -mindepth 1 -path "$src/.prsync-profiles" -prune -o -print |
            cut -c "$(($(printf '%s' "$src" | wc -c) + 1))"- \
            > "$collated_profile_path/src-include"
    fi

    $src_copy "$src/$prsync__profiles_path/$profile/exclude" "$collated_profile_path/src-exclude" 2>/dev/null
    if [ $? != 0 ]; then
        printf '' > "$collated_profile_path/src-exclude"
    fi

    $dest_copy "$dest/$prsync__profiles_path/$profile/include" "$collated_profile_path/dest-include" 2>/dev/null
    if [ $? != 0 ]; then
        find "$dest" -mindepth 1 -path "$dest/.prsync-profiles" -prune -o -print |
            cut -c "$(($(printf '%s' "$dest" | wc -c) + 1))"- \
            > "$collated_profile_path/dest-include"
    fi

    $dest_copy "$dest/$prsync__profiles_path/$profile/exclude" "$collated_profile_path/dest-exclude" 2>/dev/null
    if [ $? != 0 ]; then
        printf '' > "$collated_profile_path/dest-exclude"
    fi

    # Generate options based on profile
    local remote_port_options=()
    test "$prsync__remote_port" != '' &&
        remote_port_options=('-e' "ssh -p $prsync__remote_port")

    # Sync
    rsync \
       $(test "$write_" = false && printf '%s' '-n') \
       `# Use arrays to avoid IFS-splitting after variable expansion` \
       ${prsync__remote:+"--partial"} "${remote_port_options[@]}" \
       "${prsync__options[@]}" \
       --exclude-from="$collated_profile_path"/{src,dest}-exclude \
       --include-from="$collated_profile_path"/{src,dest}-include \
       --exclude='*' \
       {"$src","$dest"}/ \
       &> "$prsync__log_path/$direction - $profile.txt"
}
