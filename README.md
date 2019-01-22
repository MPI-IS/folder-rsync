# Description

This project aims to create a naïve parallel version of `rsync` that will try to run a configurable number of rsync instaces, one per entry in the first level folder.

Only `--dry-run`, `--delete` and `--link-dest` are parsed and taken into account (and adapted as needed). Any other option will be passed as-is to `rsync`.

## Assumptions and scope

`rsync` is a generic tool, and some use cases are beyond the scope of this tool. In particular:

* It is assumed that, if hard links are to be preserved, there are no hard links across first-level folders. If there are, they won't be copied as such, but as two different files.
* It is assumed that the last two arguments are `src` and `dst`, and that both of them are **local** directories.   

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