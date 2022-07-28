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

prsync stores the paths to two directories (that I will call 'dir1' and 'dir2') in each profile (along with some other things, see the "Config File" section). `<direction>` tells prsync whether to sync from 'dir1' to 'dir2' (`to`), or from 'dir2' to 'dir1' (`from`). The directory being synced from is called the 'source' directory and the directory being synced to is called the 'destination' directory.

**Note**: When 'dir1' is a local directory and 'dir2' is a remote directory, `to` and `from` can be thought of as 'push' and 'pull' to/from the remote host.

Your user's home directory, dir1 and dir2 must all contain a `.prsync-profiles` directory containing a subdirectory whose name matches the profile you give (the 'profile directory').

- The profile directory in your home directory (the 'home profile') must contain a file named `profile` that defines the variables set out in the "Config File" section below.
- The profile directory in the source and destination directories (the 'source profile' and 'destination profile', respectively) may contain an `include` file and/or an `exclude` file. If an include file is not present, the entire directory's contents except the `.prsync-profiles` directory (if present) is included.

**Notes**: The home, source and/or destination directories (and therefore profiles) may be the same directory. Also, the same directory could act as a source and a destination in different executions of `prsync`. For example, syncing your home directory both to and from a backup directory implies that the home and source profiles are the same directory when syncing to backup and the home and destination profiles are the same directory when syncing from backup. Therefore your home profile requires home, source, and destination profile files, while the backup requires both source and destination profile files.

When you run `prsync`, it reads the config file in the home profile, retrieves the include/exclude files from the source profile, retrieves the include/exclude files from the destination profile, then runs `rsync` with the collated information. Note that excludes are matched first, then includes, then anything that hasn't yet matched is excluded from the sync. This means the source's exclude can override the destination's include and the destination's exclude can override the source's include.

Any output of the sync (stdout only) is redirected into a log file in the directory given by `prsync__log_path`, which is `~/tmp` by default.

### Example

Commands:
```
prsync --write to backup
prsync --write from backup
```

`/home/$USER/.prsync-profiles/backup/profile`:
```
prsync__dir1="/home/$USER"
prsync__dir2="/mnt/backup/home/$USER"
prsync__options=(-aiv --delete)
```

`/mnt/backup/home/$USER/.prsync-profiles/backup/exclude`:
```
/Disk Images/***
```

`/home/$USER/.prsync-profiles/backup/include`:
```
/Documents/***
/Music/***
/Pictures/***
/Videos/***
```

Due to absence, these files are assumed to be empty:
- `/home/$USER/.prsync-profiles/backup/exclude` (nothing in home is explicitly excluded, though everything not included is implicitly excluded)
- `/mnt/backup/home/$USER/.prsync-profiles/backup/include` (everything in backup is included, except what has already been excluded)

## Config File

The primary config file in each home profile (named `profile`) must define the following variables:

- The directories:
  - `prsync__dir1` / `prsync__remote_dir1`: The path to the first directory ('dir1') must be given in *one* of these.
  - `prsync__dir2` / `prsync__remote_dir2`: The path to the second directory ('dir2') must be given in *one* of these.
  - **Notes**:
    - It is an error to specify two remote directories (this is mainly because `rsync` cannot sync between two remotes).
    - The directories may be given in either order - I would suggest assigning them to dir1/dir2 so that the `prsync` command line reads most like English, at least in the most common `<direction>`.

- The remote (only required if `dir1` or `dir2` is remote, or any of the utility functions below are used):
  - `prsync__remote`: The remote hostname or address to use. This will automatically be prepended where necessary.
  - `prsync__remote_port`: The port to use when contacting the remote server over ssh. Defaults to 22.

- `rsync` options (optional):
  - `prsync__options`: An array of options to pass to `rsync`, eg. `(-a)` or `(-rlKtOJiv --delete --sparse --human-readable)`. The default is no options.

**Note**: The `profile` config is sourced by the shell, so variables may be assigned by executing commands in a subshell (or using any other shell feature). There is also a small set of utility functions available to the config file that respond to variables already defined in the file at the point at which they are called:

- `prsync__get_remote_env <name>`
      
  Prints the value of the environment variable named `<name>` from the remote server's shell, or nothing if the variable is unset. The environment is retrived over `ssh` from the host given in `prsync__remote` on the port given in `prsync__remote_port` (if set, otherwise on the default port). This is useful for getting the home directory for the remote user, eg. `prsync__remote_dir2="$(prsync__get_remote_env HOME)"`.

- `prsync__get_remote_files_raw <options>... <source>... <dest>`

  The same as `scp`, but uses the port set in `prsync__remote_port` (if set, otherwise uses the default port). Note that the host must be included in any remote paths (see `prsync__get_remote_files` to avoid this). See `scp(1)`.

- `prsync__get_remote_files <source>... <dest>`

  The same as `prsync__get_remote_files_raw`, but prefixes all parameters except the last with the remote given in `prsync__remote` (thus avoiding having to repeat the host). Caveat: This means you can't add options to `scp`.
