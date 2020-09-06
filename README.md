# prsync

## Usage

```
prsync -h
prsync [-w] <direction> <profile>
```

Where:
- `-w` or `--write` means actually perform the sync. The default is passing `-n` to rsync to perform a dry-run.
- `direction` is either `to` or `from`. `to` uses 'dir1' from the profile (see profiles) as the source and 'dir2' as the destination. `from` is the other way around, using 'dir2' as the source and 'dir1' as the destination. When 'dir1' is a local directory and 'dir2' is a remote directory, `to` and `from` can be thought of as 'push' and 'pull' to/from the remote host.

### Example Usage

```
prsync --write to home--laptop-wsl-home
```

Where `home--laptop-wsl-home` is a profile of mine - it follows my naming convention of `dir1-description--dir2-description`, though `prsync` doesn't prescribe this.

## Description

`prsync` (meaning 'profile-based rsync') is a small wrapper around rsync that allows 'profiles' to be stored and used. Profiles are the combination of:

- A pair of directories. One of these may be remote, with the host (and optionally the port) specified separately
- A set of options to `rsync`

===========================

Ordinary profiles are stored in the '.prsync-profiles' directory in the source and destination directories. These contain the following files:

- `profile`: This is the main configuration file (executed as a shell script, so be careful) of the profile.
- `src-exclude` and `src-include`: These are the include and exclude files that are used if the directory containing '.prsync-profiles' that contains this profile
- `dest-exclude` and `dest-include`: These are the include and exclude files that are used if this profile is found in the destination.

Using the profile as a source or destination means `prsync`ing using a profile that specifies the source or destination directory (in the manner described below) that contains the profile in '<source/destination>/.prsync-profiles/<profile-name>/'
