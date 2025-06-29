prsync__profiles_path=".prsync-profiles"
prsync__log_path="$HOME/tmp"
prsync__color="color"

# Basic I/O
# --------------------------------------------------

# Adapted from:
#   https://github.com/musicmrman99/bashctl/blob/master/bashctl/helpers.def.sh

# signature: prsync__print_color_escape [color] [bold] [raw]
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
            color_seq="$(prsync__print_color_escape "$color" "$bold" false >&1)"
            normal_seq="$(prsync__print_color_escape 'normal')"
            ;;

        'rawcolor')
            color_seq="$(prsync__print_color_escape "$color" "$bold" true >&1)"
            normal_seq="$(prsync__print_color_escape 'normal')"
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

# Syntax: prsync__get_remote_env <remote_env_var>
# Outputs the value of the variable given in <remote_env_var> on the host in
# prsync__remote (connecting on the port in prsync__remote_port).
# Returns the return value of the remote shell.
function prsync__get_remote_env {
    local remote_env_var="$1"; shift

    local err="error: remote must be specified in the profile config to use \`prsync__get_remote_env\`"
    # 'local' counts as a command for $?, so declare first, then assign the
    # result of the real command
    local remote_env_val
    remote_env_val="$(ssh
        ${prsync__remote_port:+-p "$prsync__remote_port"}
        "${prsync__remote:?$err}"
        "env | grep '^$remote_env_var=' | sed 's/^$remote_env_var=//'"
    )"

    local result="$?"
    printf '%s' "$remote_env_val"
    return "$result"
}

# Syntax: prsync__get_target <remote> <path> [force_escape]
# - remote is the `user@host` to use. May be empty.
# - path is the path on that host, or a local path if <remote> is empty.
# - force_escape is an optional parameter to force the resulting path part to be
#   escaped or not. May be true (force escaping) or false (force no escaping).
#   If omitted, escaping is done if <remote> is non-empty.
function prsync__get_target {
    local remote="$1"; shift
    local path="$1"; shift
    local force_escape="$1"; shift

    if [ "$remote" != '' ]; then
        printf '%s:' "$remote"
    fi

    local format_spec='%s' # If invalid params
    if [ \
        "$force_escape" = false -o \
        \( "$force_escape" = '' -a "$remote" = '' \) \
    ]; then
        # Local paths don't need escaping [cross-platform???]
        format_spec='%s'

    elif [ \
        "$force_escape" = true -o \
        \( "$force_escape" = '' -a "$remote" != '' \) \
    ]; then
        # Remote paths need escaping for ssh/scp/rsync
        # Notes:
        #   "${var_name@Q}" (quote variable value, or each element if an array;
        #   see https://stackoverflow.com/a/12985353) doesn't work with scp due
        #   to https://stackoverflow.com/a/54599326. `scp -T` (a work-around) is
        #   less safe (see 2nd link), so use printf's backslash-escape format
        #   specifier (%q) instead (Bash 4.0+).
        format_spec='%q'
    fi
    printf "$format_spec" "$path"
}

# Syntax: prsync__get_files <remote> <paths...> <dest>
# - remote is the `user@host` to use. May be empty.
# - paths are the paths to copy from that host, or from the local machine if
#   <remote> is empty.
# - dest is the local directory to copy the files to.
function prsync__get_files {
    local remote="$1"; shift

    # Exclude the 0th parameter (which is always '-bash') and last parameter
    # (which is the destination path, and is expected to be local, so doesn't
    # require escaping)
    local all_but_last=()
    for ((i = 1; i < ${#@}; i++)); do
        all_but_last[i]="$(prsync__get_target "$remote" "${!i}")"
    done

    # Copy the file(s)
    if [ "$remote" = '' ]; then
        cp "${all_but_last[@]}" "${!#}"
    else
        scp -q ${prsync__remote_port:+-P "$prsync__remote_port"} \
            "${all_but_last[@]}" "${!#}"
    fi
    return $?
}

# Syntax: prsync__get_files_remote <paths...> <dest>
# Same as prsync__get_files, except binds prsync__remote to the <remote>
# parameter. Errors if prsync__remote is empty (or undefined).
function prsync__get_files_remote {
    local err="error: remote must be specified in the profile config to use \`prsync__get_files_remote\`"
    prsync__get_files "${prsync__remote:?$err}" "$@"
    return $?
}

# Syntax: prsync__put_files <remote> <paths...> <dest>
# - remote is the `user@host` to use. May be empty.
# - paths are the local paths to copy from.
# - dest is the (possibly remote) directory to copy the files to.
function prsync__put_files {
    local remote="$1"; shift

    # Copy the file(s)
    if [ "$remote" = '' ]; then
        cp "${@:1:${#@}-1}" "$(prsync__get_target "$remote" "${!#}")"
    else
        scp -q ${prsync__remote_port:+-P "$prsync__remote_port"} \
            "${@:1:${#@}-1}" "$(prsync__get_target "$remote" "${!#}")"
    fi
    return $?
}

# Syntax: prsync__put_files_remote <paths...> <dest>
# Same as prsync__put_files, except binds prsync__remote to the <remote>
# parameter. Errors if prsync__remote is empty (or undefined).
function prsync__put_files_remote {
    local err="error: remote must be specified in the profile config to use \`prsync__put_files_remote\`"
    prsync__put_files "${prsync__remote:?$err}" "$@"
    return $?
}

# Syntax: prsync__find <remote> <dir> [find_options...]
function prsync__find {
    local remote="$1"; shift

    # Find files
    if [ "$remote" = '' ]; then
        find "$@"
    else
        # Exclude the 0th parameter (which is always '-bash') and last parameter
        # (which is the destination path, and is expected to be local, so
        # doesn't require escaping)
        # FIXME: Also escape all arguments. Using prsync__get_target for this is
        #        a minor hack (as arguments are not all paths), but for now it's
        #        better to make all escaping use the same function.
        local escaped=()
        for ((i = 1; i <= ${#@}; i++)); do
            escaped[i]="$(prsync__get_target '' "${!i}" true)"
        done

        ssh ${prsync__remote_port:+-p "$prsync__remote_port"} "$remote" \
            find "${escaped[@]}"
    fi
    return $?
}

# Syntax: prsync__find_remote <paths...> <dest>
# Same as prsync__find, except binds prsync__remote to the <remote>
# parameter. Errors if prsync__remote is empty (or undefined).
function prsync__find_remote {
    local err="error: remote must be specified in the profile config to use \`prsync__find_remote\`"
    prsync__find "${prsync__remote:?$err}" "$@"
    return $?
}

# Unset all variables defined by prsync__load_profile
function prsync__unload_active_profile {
    unset prsync__options
    unset prsync__dir1
    unset prsync__dir2
    unset prsync__dir1_remote
    unset prsync__dir2_remote
    unset prsync__remote
    unset prsync__remote_port
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
        prsync__dir1_remote="${prsync__remote:?$err}"
        prsync__dir1="$prsync__remote_dir1"

        err="error: dir2 must be specified in the profile config and not be remote, as dir1 is remote"
        prsync__dir2_remote=""
        prsync__dir2="${prsync__dir2:?$err}"

    elif [ "$prsync__remote_dir2" != '' ]; then
        err="error: dir1 must be specified in the profile config and not be remote, as dir2 is remote"
        prsync__dir1_remote=""
        prsync__dir1="${prsync__dir1:?$err}"

        err="error: remote must be specified in the profile config, as dir2 is remote"
        prsync__dir2_remote="${prsync__remote:?$err}"
        prsync__dir2="$prsync__remote_dir2"

    else
        err="error: dir1 (prsync__dir1 or prsync__remote_dir1) must be specified in the profile config"
        prsync__dir1_remote=""
        prsync__dir1="${prsync__dir1:?$err}"

        err="error: dir2 (prsync__dir2 or prsync__remote_dir2) must be specified in the profile config"
        prsync__dir2_remote=""
        prsync__dir2="${prsync__dir2:?$err}"
    fi

    # Unset profile variables that are no longer needed
    unset prsync__remote_dir1
    unset prsync__remote_dir2
}

# Actions / Sub-Commands
# --------------------------------------------------

function prsync__help {
    if command -v mdless &> /dev/null; then
        mdless "$prsync_dir/README.md"
    else
        less "$prsync_dir/README.md"
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
            prsync__load_profile "$profile" # Source it to eval the paths
            prsync__print 'white' false \
                '    %s\n      V | %s\n    %s\n\n' \
                "$(prsync__get_target "$prsync__dir1_remote" "$prsync__dir1" false)" \
                "${prsync__options[*]}" \
                "$(prsync__get_target "$prsync__dir2_remote" "$prsync__dir2" false)"
        fi

    done < <( # Process substitution
        find "$HOME/$prsync__profiles_path/" -name 'profile' -print0 |
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
    local src dest src_remote dest_remote
    case "$direction" in
        'to')
            src="$prsync__dir1" && src_remote="$prsync__dir1_remote"
            dest="$prsync__dir2" && dest_remote="$prsync__dir2_remote"
            ;;

        'from')
            src="$prsync__dir2" && src_remote="$prsync__dir2_remote"
            dest="$prsync__dir1" && dest_remote="$prsync__dir1_remote"
            ;;
    esac

    # Create/clear log file for this profile
    printf '' > "$prsync__log_path/$direction - $profile_flat.log"

    # Retrieve src and dest rsync include/exclude files from their respective
    # profiles
    local collated_profile_path="$HOME/$prsync__profiles_path/$profile/collated-profile"

    test ! -d "$collated_profile_path" &&
        mkdir "$collated_profile_path" ||
        rm "$collated_profile_path"/*

    prsync__get_files "$src_remote" \
        "$src/$prsync__profiles_path/$profile/include" \
        "$collated_profile_path/src-include" \
        2>/dev/null
    if [ $? != 0 ]; then
        prsync__find "$src_remote" \
            "$src" \
            -mindepth 1 \
            -path "$src/$prsync__profiles_path" -prune \
            -o -print \
            2>> "$prsync__log_path/$direction - $profile_flat.log" \
            | cut -c "$(($(printf '%s' "$src" | wc -c) + 1))"- \
            > "$collated_profile_path/src-include"
    fi

    prsync__get_files "$src_remote" \
        "$src/$prsync__profiles_path/$profile/exclude" \
        "$collated_profile_path/src-exclude" \
        2>/dev/null
    if [ $? != 0 ]; then
        printf '' > "$collated_profile_path/src-exclude"
    fi

    prsync__get_files "$dest_remote" \
        "$dest/$prsync__profiles_path/$profile/include" \
        "$collated_profile_path/dest-include" \
        2>/dev/null
    if [ $? != 0 ]; then
        prsync__find "$dest_remote" \
            "$dest" \
            -mindepth 1 \
            -path "$dest/$prsync__profiles_path" -prune \
            -o -print \
            2>> "$prsync__log_path/$direction - $profile_flat.log" \
            | cut -c "$(($(printf '%s' "$dest" | wc -c) + 1))"- \
            > "$collated_profile_path/dest-include"
    fi

    prsync__get_files "$dest_remote" \
        "$dest/$prsync__profiles_path/$profile/exclude" \
        "$collated_profile_path/dest-exclude" \
        2>/dev/null
    if [ $? != 0 ]; then
        printf '' > "$collated_profile_path/dest-exclude"
    fi

    # Update timestamp in destination profile if writing
    if [ "$write_" = true ]; then
        echo "$(date -Is)" > /tmp/prsync__last-write
        prsync__put_files "$dest_remote" \
            /tmp/prsync__last-write \
            "$dest/$prsync__profiles_path/$profile/last-write"
    fi

    # Generate additional rsync options based on profile
    local remote_port_options=()
    test "$prsync__remote_port" != '' &&
        remote_port_options=('-e' "ssh -p $prsync__remote_port")

    # Sync
    rsync \
        $(test "$write_" = false && printf '%s' '-n') \
        ${prsync__remote:+"--partial"} "${remote_port_options[@]}" \
        "${prsync__options[@]}" \
        --exclude-from="$collated_profile_path"/{src,dest}-exclude \
        --include-from="$collated_profile_path"/{src,dest}-include \
        --exclude='*' \
        "$(prsync__get_target "$src_remote" "$src/")" \
        "$(prsync__get_target "$dest_remote" "$dest/")" \
        1> "$prsync__log_path/$direction - $profile_flat.txt" \
        2>> "$prsync__log_path/$direction - $profile_flat.log"
}

# Switchboard
# --------------------------------------------------

# 'profile rsync'
function prsync {
    # The following is a modified version of this:
    #   http://stackoverflow.com/a/246128
    local prsync_source
    local prsync_dir

    prsync_source="${BASH_SOURCE[0]}"

    # Resolve $prsync_source until the file is no longer a symlink
    while [ -h "$prsync_source" ]; do
        prsync_dir="$(cd -P "$( dirname "$prsync_source" )" && pwd)"
        prsync_source="$(readlink "$prsync_source")"

        # If $prsync_source was a relative symlink, we need to resolve it
        # relative to the path where the symlink file was located
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
