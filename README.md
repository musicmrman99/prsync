# prsync

`prsync` (profile-based rsync) is a small wrapper around `rsync` that allows sync directories and options to be stored in files, and uses safer (and arguably more intuitive) defaults.

## Synopsis

```sh
prsync help
prsync list [verbose]
prsync preview (to | from) <profile>
prsync write (to | from) <profile>
```

## Description

`prsync` is a tool for managing 'profiles' that store information about synchronising two directories with `rsync`. Profiles are directories below the profiles directory (`$HOME/.prsync-profiles`) containing a `profile` file that is a source-able shell script that defines the variables described in the [Profile File](#profile-file) section. This primarily includes defining as variables the paths to the two directories to sync (called 'dir1' and 'dir2' in these docs) and a set of options that are passed to `rsync`. `prsync`'s functionality is split into sub-commands.

## Commands

- `prsync (help | --help | -h | -?)`
  Show this help text.

- `prsync (list | --list | -l) [verbose | --verbose | -v]`
  Lists all available profiles. If `verbose` is specified, then for each profile, also print the two directories it syncs and its sync options.

- `prsync (preview | --preview | -p) (to | from) <profile>`
- `prsync (write | --write | -w) (to | from) <profile>`
  Previews (`preview`) or performs (`write`) a file sync in the given direction, using the given profile.

  Arguments:
    `to` or `from` tells prsync whether to sync from dir1 to dir2 (`to`), or from dir2 to dir1 (`from`). In these docs, the directory being synced from is called the 'source' directory and the directory being synced to is called the 'destination' directory. Note that when dir1 is a local directory and dir2 is a remote directory, `to` and `from` can be thought of as 'push' and 'pull' to/from the remote host. This argument only matters when certain `rsync` options are specified in the profile, such as `--delete`, but it is required regardless (**TODO**).

    `<profile>` specifies which profile to use. Profiles are referred to by their directory name, eg. `prsync -p to example-profile` would expect the file `$HOME/.prsync-profiles/example-profile/profile` to exist and define the relevant variables. This name includes any directories the profile is nested in below the profiles directory, eg. `prsync -p to example/nested-profile` would expect the file `$HOME/.prsync-profiles/example/nested-profile/profile`) to exist and define the relevant variables.

  Details:
    Previewing the sync performs the same steps as performing the sync, except that no files are changed.
    
    dir1 and dir2 may each have a profiles directory (`.prsync-profiles`) containing the `<profile>` used, which may contain an `include` file and/or an `exclude` file that will be passed to the `--include-from` and `--exclude-from` options of `rsync` to determine the subset of files to consider in the sync (sync `man rsync` for details of the syntax of these files). For each side of the sync that omits an `include` file, `prsync` includes the entire contents of the directory for that side, except the profiles directory, if present. For each side that omits an `exclude` file, it is considered empty for that side. Using `rsync`'s "first match wins" rule, the `exclude` files are considered first, then the `include` files, then everything not matched is excluded. This mechanism has two important effects. First, the source's exclude can override the destination's include and the destination's exclude can override the source's include. Second, the effect that when all files are omitted (the 'default'), `prsync` works the same as `rsync` (except for omitting `prsync`'s own metadata files), but for each side that gives its `include` file, `prsync` assumes everything is excluded on that side unless explicitly included, which is the opposite way around to `rsync`, which assumes everything is included unless explicitly excluded. **These effects make syncs less error-prone**.

    All normal output of the sync is written to a text (`.txt`) file named the same as the given profile (with any directory separators replaced with underscores) in the directory given in the `prsync__log_path` variable, which is `~/tmp` by default. All error output of the sync is written to a log (`.log`) file with the same name in the same directory.

    In full: when you run `prsync -p`/`prsync -w`, it:
    - Reads the `profile` file in the home profile
    - Retrieves the include/exclude files from dir1's and dir2's profile directories, generating defaults if any are omitted
    - Runs `rsync` with the collated information
    - Writes all normal output to `$prsync__log_path/$profile.txt`
    - Writes all error output to `$prsync__log_path/$profile.log`

**Note**: The profiles directory's name (`.prsync-profiles` by default) can be set using the `prsync__profiles_path` global variable, but rarely needs to be changed.

## Profile File

The `profile` file in each profile must define the following variables:

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

**Note**: The `profile` is sourced by the shell, so variables may be assigned by executing commands in a subshell, or using any other shell feature. There is also a small set of utility functions available to the `profile` file that respond to variables already defined in the file at the point at which those functions are called:

- `prsync__get_remote_env <name>`
  Prints the value of the environment variable named `<name>` from the remote server's shell, or nothing if the variable is unset. The environment is retrived over `ssh` from the host given in `prsync__remote` on the port given in `prsync__remote_port` (if set, otherwise on the default port). This is useful for getting the home directory for the remote user, eg. `prsync__remote_dir2="$(prsync__get_remote_env HOME)"`.

- `prsync__get_remote_files_raw <options>... <source>... <dest>`
  The same as `scp`, but uses the port set in `prsync__remote_port` (if set, otherwise uses the default port). Note that the host must be included in any remote paths (see `prsync__get_remote_files` to avoid this). See `scp(1)`.

- `prsync__get_remote_files <source>... <dest>`
  The same as `prsync__get_remote_files_raw`, but prefixes all parameters except the last with the remote given in `prsync__remote` (thus avoiding having to repeat the host). Caveat: This means you can't add options to `scp`.

## Example

Commands:
```sh
prsync write to backup
prsync write from backup
```

`/home/$USER/.prsync-profiles/backup/profile`:
```sh
prsync__dir1="$HOME"
prsync__dir2="/mnt/backup/$HOME"
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

Due to omission, these files take the following defaults:

- `$HOME/.prsync-profiles/backup/exclude`
  - Nothing in home is explicitly excluded, though everything not included is implicitly excluded.

- `/mnt/backup/$HOME/.prsync-profiles/backup/include`
  - Everything in backup is included, except what has already been excluded.
