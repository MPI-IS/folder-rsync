# Description

This project aims to create a naïve parallel version of `rsync` that will try to run a configurable number of rsync instaces, one per entry in the first level folder.

Only `--dry-run`, `--delete` and `--link-dest` are parsed and taken into account (and adapted as needed). Any other option will be passed as-is to `rsync`.

## Assumptions and scope

`rsync` is a generic tool, and some use cases are beyond the scope of this tool. In particular:

* It is assumed that, if hard links are to be preserved, there are no hard links across first-level folders. If there are, they won't be copied as such, but as two different files.
* It is assumed that the last two arguments are `src` and `dst`, and that both of them are **local** directories. The behavior of trailing slashes is mimicked, modulo bugs.

# Usage

`folder_rsync <regular rsync command line options>`

## Environment variables

* `OMP_NUM_THREADS` overrides the number of threads to be creates.
* `LOG` sets the log level. The possible options, in order of descending detail, are:
  * all
  * trace
  * info
  * warning
  * error
  * critical
  * fatal
  * off

## Return codes

It's really impossible to forward all the information concerning the different children processes. In order to offer a somewhat useful result code, the following rules are used:

* If there is no error, then no error (status 0) is returned.
* The first status code will be returned, unless it is a "file vanished" issue, which should be harmless.
* "File vanished" (status 24) will only be returned if it's the only non-zero return code from the different  