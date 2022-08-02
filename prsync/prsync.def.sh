prsync__profiles_path=".prsync-profiles"
prsync__log_path="$HOME/tmp"
prsync__color="color"

# Basic I/O
# --------------------------------------------------

# Adapted from https://github.com/musicmrman99/bashctl/blob/master/bashctl/helpers.def.sh

# signature: bashctl__print_color_escape [color] [bold] [raw]
function prsync__print_color_escape {
    local color="$1"; shift
    local bold="$1"; shift
    local raw="$1"; shift

    local color_string='0'
    case "$color" in
        'black') color_string='30';;
        'red') color_string='31';;
        'green') color_string='32';;
        'orange') color_string='33';;
        'blue') color_string='34';;
        'magenta') color_string='35';;
        'turquoise') color_string='36';;
        'white') color_string='37';;
    esac

    local bold_string=''
    if [ "$bold" = 'bold' ]; then bold_string='01;'; fi

    local raw_string=''
    if [ "$raw" = 'bold' ]; then raw_string='\\\'; fi

    printf '%s' "${raw_string}\033[${bold_string}${color_string}m"
}

# signature: prsync__print color bold format [object [...]]
function prsync__print {
    local color="$1"; shift
    local bold="$1"; shift
    local format="$1"; shift

    local color_seq
    local normal_seq
    case "$prsync__color" in
        'color')
            color_seq="$(bashctl__print_color_escape "$color" "$bold" false >&1)"
            normal_seq="$(bashctl__print_color_escape 'normal')"
            ;;

        'rawcolor')
            color_seq="$(bashctl__print_color_escape "$color" "$bold" true >&1)"
            normal_seq="$(bashctl__print_color_escape 'normal')"
            ;;

        'plain')
            color_seq=''
            normal_seq=''
            ;;
    esac

    printf "${color_seq}${format}${normal_seq}" "$@"
}

# Profile Utils
# --------------------------------------------------

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

# Unset all variables that could be defined by prsync__load_profiles
function prsync__unload_active_profile {
    unset prsync__options
    unset prsync__dir1
    unset prsync__dir2
    unset prsync__remote_dir1
    unset prsync__remote_dir2
    unset prsync__remote
    unset prsync__remote_port
    unset prsync__final_dir1
    unset prsync__final_dir2
}

# Load a prsync profile (defines some combination of the variables listed above)
function prsync__load_profile {
    local profile="$1"; shift

    prsync__unload_active_profile
    .  "$HOME/$prsync__profiles_path/$profile/profile"

    # Used to store error messages for unset/null parameter expansion
    local err

    # Verify the configuration and extract variables
    if [ "$prsync__remote_dir1" != '' -a "$prsync__remote_dir2" != '' ]; then
        # Both dir1 and dir2 being remote is an error - rsync can't do that
        printf '%s\n' "error: src and dest cannot both be remote"
        return 1

    elif [ "$prsync__remote_dir1" != '' ]; then
        err="error: remote must be specified in the profile config, as dir1 is remote"
        prsync__final_dir1="${prsync__remote:?$err}:$prsync__remote_dir1"

        err="error: dir2 must be specified in the profile config and not be remote, as dir1 is remote"
        prsync__final_dir2="${prsync__dir2:?$err}"

    elif [ "$prsync__remote_dir2" != '' ]; then
        err="error: dir1 must be specified in the profile config and not be remote, as dir2 is remote"
        prsync__final_dir1="${prsync__dir1:?$err}"

        err="error: remote must be specified in the profile config, as dir1 is remote"
        prsync__final_dir2="${prsync__remote:?$err}:$prsync__remote_dir2"

    else
        err="error: dir1 must be specified in the profile config"
        prsync__final_dir1="${prsync__dir1:?$err}"

        err="error: dir2 must be specified in the profile config"
        prsync__final_dir2="${prsync__dir2:?$err}"
    fi
}

# Actions / Sub-Commands
# --------------------------------------------------

function prsync__help {
    if command -v mdless &> /dev/null; then
        mdless "$prsync_dir/help/README.md"
    else
        less "$prsync_dir/help/README.md"
    fi
}

function prsync__list {
    local verbose=false
    case "$1" in
        'verbose' | '--verbose' | '-v') shift; verbose=true;;
    esac

    local profile
    while IFS= read -r -d $'\0' profile; do
        # Output Profile
        local leading="$(printf '%s' "$profile" | rev | cut -d '/' -f 2- | rev)"
        local last="$(printf '%s' "$profile" | rev | cut -d '/' -f 1 | rev)"

        if [ "$leading" != "$last" ]; then
            prsync__print 'turquoise' false '%s' "$leading/"
        fi
        prsync__print 'blue' true '%s\n' "$last"

        if [ "$verbose" = true ]; then
            # Output Profile Endpoints & Options
            prsync__load_profile "$profile" # Source it to get the path, not the code
            prsync__print 'white' false \
                '    %s\n      V | %s\n    %s\n\n' \
                "$prsync__final_dir1" "${prsync__options[*]}" "$prsync__final_dir2"
        fi

    done < <( # Process substitution
        find "$HOME/$prsync__profiles_path" -name 'profile' -print0 |
        sort -z |
        xargs -0 -I{} sh -c "printf '%s\0' \"\$(
            dirname {} |
            cut -c $(($(printf '%s' "$HOME/$prsync__profiles_path" | wc -c) + 2))-
        )\""
    )
}

function prsync__sync {
    local write_="$1"; shift

    # Get positional params: sync direction, profile to use
    local direction
    if [ "$1" = '' ]; then
        printf 'error: no direction given\n'
        return 1
    else
        case "$1" in
            'to' | 'from') direction="$1"; shift;;
            *)
                printf "unrecognised value for 'direction' parameter: '%s'" "$1"
                return 1
                ;;
        esac
    fi

    local profile
    local profile_flat
    if [ "$1" = '' ]; then
        printf 'error: no profile given\n'
        return 1
    else
        profile="$1"; shift
        profile_flat="$(printf '%s' "$profile" | sed -e 's#/#_#g')"
    fi

    # Load profile
    prsync__load_profile "$profile"

    # Determine source & dest directories and how to get profiles from them
    local src dest
    if [ "$direction" = 'to' ]; then
        src="$prsync__final_dir1" && dest="$prsync__final_dir2"
    else
        src="$prsync__final_dir2" && dest="$prsync__final_dir1"
    fi

    local src_copy dest_copy
    if [ "$prsync__remote_dir1" != '' ]; then
        case "$direction" in
            'to') src_copy="prsync__get_remote_files_raw" && dest_copy="cp";;
            'from') src_copy="cp" && dest_copy="prsync__get_remote_files_raw";;
        esac

    elif [ "$prsync__remote_dir2" != '' ]; then
        case "$direction" in
            'to') src_copy="cp" && dest_copy="prsync__get_remote_files_raw";;
            'from') src_copy="prsync__get_remote_files_raw" && dest_copy="cp";;
        esac

    else
        src_copy="cp" && dest_copy="cp"
    fi

    # Retrieve src and dest rsync include/exclude files from their respective profiles
    local collated_profile_path="$HOME/$prsync__profiles_path/$profile/collated-profile"

    test ! -d "$collated_profile_path" &&
        mkdir "$collated_profile_path" ||
        rm "$collated_profile_path"/*

    $src_copy "$src/$prsync__profiles_path/$profile/include" "$collated_profile_path/src-include" 2>/dev/null
    if [ $? != 0 ]; then
        find "$src" -mindepth 1 -path "$src/.prsync-profiles" -prune -o -print 2>> "$prsync__log_path/$direction - $profile_flat.log" |
            cut -c "$(($(printf '%s' "$src" | wc -c) + 1))"- \
            > "$collated_profile_path/src-include"
    fi

    $src_copy "$src/$prsync__profiles_path/$profile/exclude" "$collated_profile_path/src-exclude" 2>/dev/null
    if [ $? != 0 ]; then
        printf '' > "$collated_profile_path/src-exclude"
    fi

    $dest_copy "$dest/$prsync__profiles_path/$profile/include" "$collated_profile_path/dest-include" 2>/dev/null
    if [ $? != 0 ]; then
        find "$dest" -mindepth 1 -path "$dest/.prsync-profiles" -prune -o -print 2>> "$prsync__log_path/$direction - $profile_flat.log" |
            cut -c "$(($(printf '%s' "$dest" | wc -c) + 1))"- \
            > "$collated_profile_path/dest-include"
    fi

    $dest_copy "$dest/$prsync__profiles_path/$profile/exclude" "$collated_profile_path/dest-exclude" 2>/dev/null
    if [ $? != 0 ]; then
        printf '' > "$collated_profile_path/dest-exclude"
    fi

    # Update timestamp in destination profile if writing
    if [ "$write_" = true ]; then
        echo "$(date -Is)" > "$dest/$prsync__profiles_path/$profile/last-write"
    fi

    # Generate additional rsync options based on profile
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
        1> "$prsync__log_path/$direction - $profile_flat.txt" \
        2>> "$prsync__log_path/$direction - $profile_flat.log"
}

# Switchboard
# --------------------------------------------------

# 'profile rsync'
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

    local action="$1"; shift
    case "$action" in
        'help'    | '--help'    | '-h' | '-?') prsync__help "$@";;
        'list'    | '--list'    | '-l') prsync__list "$@";;
        'preview' | '--preview' | '-p') prsync__sync false "$@";;
        'write'   | '--write'   | '-w') prsync__sync true "$@";;
        *)
            printf "unrecognised action: '%s'\n" "$action"
            return 1;;
    esac
}
