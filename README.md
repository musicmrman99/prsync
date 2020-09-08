# prsync

`prsync` (meaning "profile-based rsync") is a small wrapper around rsync that allows *profiles* to be stored and used.

## Usage

```
prsync -h
prsync [-w] <direction> <profile>
```

The first form prints the help text. The second form performs a file sync in the given direction, using the given profile.

Options:

- `-h`, `-?`, `--help`: Print the help text.
- `-w`, `--write`: Tells `prsync` to actually perform the sync. The default is passing `-n` to rsync to perform a dry-run.

## Overview

prsync stores the paths to two directories (that I'll call 'dir1' and 'dir2') in each profile (along with some other things). `<direction>` tells prsync whether to sync from 'dir1' to 'dir2' (`to`), or from 'dir2' to 'dir1' (`from`). The directory being synced from is called the 'source' directory and the directory being synced to is called the 'destination' directory.

**Note**: When 'dir1' is a local directory and 'dir2' is a remote directory, `to` and `from` can be thought of as 'push' and 'pull' to/from the remote host.

Your user's home directory, and the source and destination directories must all contain a `.prsync-profiles` directory and the given `<profile>` must be a present in each:

- The profile in your home folder is given the role of the 'main profile', and must be a valid main profile
- The profile in the source is given the role of the 'source profile', and must be a valid source profile
- The profile in the destination is given the role of the 'destination profile', and must be a valid destination profile

A profile is a valid:

- 'main profile' if it contains a main config file named `profile` that defines the variables set out below
- 'source profile' if it contains the source include/exclude files (`src-include` and `src-exclude`)
- 'destination profile' if it contains the destination include/exclude files (`dest-include` and `dest-exclude`)

**Note**: It is possible for the same directory to be valid to be used for more than one profile role. The same directory could act as a source and a destination profile in different runs of `prsync` if the directory that contains the profile is both synced `to` and synced `from` the other directory. Also, the same directory must act as both a main profile and a source *or* destination profile simultaneously when syncing from or to your home folder, respectively.

When you run `prsync`, it reads the config file in the main profile, retrieves the source include/exclude files from the source profile, retrieves the destination include/exclude files from the destination profile, then runs `rsync` with the collated information. Note that excludes are matched first, then includes, then anything that hasn't yet matched is excluded from the sync. This means the source's exclude can override the destination's include and the destination's exclude can override the source's include.

Any output of the sync (stdout only) is redirected into a log file in the folder given by `prsync__log_path`, which is `~/tmp` by default.

### Example

```
prsync --write to desktop-home--laptop-wsl-home
```

Where `desktop-home--laptop-wsl-home` is the name of a profile. That profile name follows my naming convention of `dir1-description--dir2-description`, though `prsync` doesn't prescribe this.

## The Config File

The primary config file in each 'main' profile is named `profile` and must define the following variables:

- The directories:
  - `prsync__dir1` / `prsync__remote_dir1`: The path to the first directory ('dir1') must be given in *one* of these.
  - `prsync__dir2` / `prsync__remote_dir2`: The path to the second directory ('dir2') must be given in *one* of these.
  - **Notes**:
    - It is an error to specify two remote directories (this is mainly because `rsync` cannot sync between two remotes).
    - The directories may be given in either order - I would suggest writing them in the order that makes the `prsync` command line read most like English.

- The remote (only required if `dir1` or `dir2` is remote, or any of the utility functions below are used):
  - `prsync__remote`: The remote hostname or address to use. This will automatically be prepended where necessary.
  - `prsync__remote_port`: The port to use when contacting the remote server over ssh. This defaults to port 22.

- `rsync` options (optional):
  - `prsync__options`: An array of options to pass to `rsync`, eg. `(-a)` or `(-rlKtOJiv --delete --sparse --human-readable)`. The default is no options.

**Note**: The `profile` config is sourced by the shell, so variables may be assigned by executing commands in a subshell (using `` `command` `` or `$(command)` syntax). There is also a small set of utility functions available to the config file that both respond to variables already defined in the file:

- `prsync__get_remote_env <name>`
      
  Prints the value of the environment variable named `<name>` from the remote server's shell, or nothing if the variable is unset. The environment is retrived over `ssh` from the host given in `prsync__remote` on the port given in `prsync__remote_port` (if set, otherwise on the default port). This is useful for getting the home directory for the remote user, ie. `prsync__remote_dir2="$(prsync__get_remote_env HOME)"`.

- `prsync__get_remote_files_raw <options>... <source>... <dest>`

  The same as `scp`, but uses the port set in `prsync__remote_port` (if set, otherwise uses the default port). Note that the host must be included in any remote paths (see `prsync__get_remote_files` to avoid this). See `scp(1)`.

- `prsync__get_remote_files <source>... <dest>`

  The same as `prsync__get_remote_files_raw`, but prefixes all parameters except the last with the remote given in `prsync__remote` (thus avoiding having to repeat the host). Caveat: This means you can't add options to `scp`.
