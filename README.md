# ungit

Fetch the content of a forge's repository at a given reference into a local
directory. [`ungit`](./ungit.sh) uses the various forge APIs, thus entirely
bypasses `git`. You will get a snapshot of the repository at that reference,
with no history. In most cases, this is [quicker](#speed) than cloning the
repository. `ungit` also implements a GitHub action, with a behaviour and inputs
similar to [actions/checkout], but without the history.

`ungit` can detect that the destination directory belongs to a git repository.
In that case it will maintain an index of such snapshots in a file called
`.ungit` at the root of the repository, preferrably. `ungit` automatically
caches tarballs in the [XDG] cache to avoid unecessary downloads.

Read further down for a more detailed list of `ungit`'s [features](#highlights)
and [limitations](#limitations), or jump straight to the [examples](#examples).

  [actions/checkout]: https://github.com/actions/checkout

## Examples

### Basic Usage

#### Fetch from `main` branch at GitHub

Provided `ungit.sh` is in your `$PATH`, the following command will download the
latest content of this repository (`main` branch) into a directory called
`ungit` under the current directory.

```bash
ungit.sh add efrecon/ungit
```

The `add` command is optional, this means that the command below is similar:

```bash
ungit.sh efrecon/ungit
```

#### Specify a branch/tag/reference

The following command will download the first version ever committed to this
repository to the directory `/tmp/ungit`. The reference can either be a branch
name, a tag or, as in the example, a commit reference.

```bash
ungit.sh add efrecon/ungit@34bc76507d0e7722811720532587dd6547e8893a /tmp/ungit
```

#### Download from GitLab

The following command will download the `renovate/golang-1.x` branch from the
GitLab Runner project. Verbosity feedback is provided, increase the number of
`v`s for even more details.

```bash
ungit.sh -t gitlab -v add gitlab-org/gitlab-runner@renovate/golang-1.x
```

### Index File

Some of the examples below point explicitely to an index file called `.ungit`.
If they were called from a directory contained in a git repository, it is
possible to omit the `-i` option instead, as it is the default. By default,
`ungit` will automatically climb up the hierarchy starting from the destination
directory to look for the `.ungit` file when adding, installing or deleting.

#### Add a Snapshot

The following command will download the latest content of this repository
(`main` branch) into a directory called `ungit` under the current directory. It
will update the index file called `.ungit` in the current directory to remember
this association.

```bash
ungit.sh -i .ungit add efrecon/ungit
```

#### Install Several Snapshots

Edit the `.ungit` file to the following content:

```text
ungit https://github.com/efrecon/ungit

# Add (but rename) the gh-action-keepalive project
actions/keepalive https://github.com/efrecon/gh-action-keepalive
```

Then, when the following command is run, it will add the `ungit` and
`actions/keepalive` directories under the current directory. `ungit` will
automatically climb up the hierarchy in search for the `.ungit` index file that
you have created. Since an index file is found and used, files and directories
will be made read-only. This is to enforce managing the snapshots using `ungit`,
and to prevent their heedless modification.

```bash
ungit.sh install
```

#### Remove a Snapshot

Building upon the previous example, the following command will remove the
`ungit` directory from under the current directory and remove the association
from the index file. In the example below, specifying the `.ungit` index file is
redundant.

```bash
ungit.sh -i .ungit remove ungit
```

### As a GitHub Action

#### Checkout Current Project

Checkout the current project at the current reference, in the current workspace
at the runner.

```yaml
- uses: efrecon/ungit
```

#### Checkout Another Project

Checkout the `efrecon/ungit` project, at a given reference in the current
workspace at the runner.

```yaml
- uses: efrecon/ungit
  with:
    repository: efrecon/ungit
    ref: 34bc76507d0e7722811720532587dd6547e8893a
```

## Usage

### Script

The behaviour of [`ungit`](./ungit.sh) is controlled by a series of environment
variables -- all starting with `UNGIT_` -- and by its command-line (short)
options. Options have precedence over environment variables. The first argument
to `ungit` is a command, and this command defaults to `add`. Provided `ungit.sh`
is in your `$PATH`, run the following command to get help over both the
variables, the CLI options and commands.

```bash
ungit.sh -h
```

`ungit` recognises the following commands as its first argument, after its
options:

+ `add`: Add a snapshot of the repository passed as a first argument to the
  directory passed as a second argument (optional). When an index file is to be
  maintained, it will remember the association. The index file will contain a
  relative reference to the destination directory.
+ `delete` (or `remove`): Remove the directory passed as an argument. When an
  index file is to be maintained, the association will be lost.
+ `install`: Install snapshots of all repositories pointed out by the index
  file, if not already present.
+ `help`: Print the same help as with the `-h` option and exit.

This script has minimal dependencies. It has been tested under `bash` and `ash`
and will be able to download content as long as `curl` (preferred) or `wget`
(including the busybox version) are available at the `$PATH`.

### GitHub Action

The GitHub Action uses inputs named after the ones of [actions/checkout]. It is
a composite action that interfaces almost 1-1 the [`ungit`](./ungit.sh)
implementation script. For an exact list of inputs, consult the
[action](./action.yml).

## Highlights

+ Takes either the full URL to a repository, or its owner/name as a first
  parameter. When only an owner/name is provided, the URL is constructed out of
  the value of the `-t` option -- `github` by default.
+ Keeps a cache of downloaded tarballs under a directory called `ungit` in the
  [XDG] cache directory. Cached tarballs are reused if possible, unless the
  `-ff` option is provided (yes: twice the `-f` option!).
+ Will not overwrite the content of the target directory if it already exists,
  unless the `-f` option is provided.
+ When APIs provide a way to make the difference, the search order for the
  reference is: branch name, tag name, pull request, commit reference.
+ When running against GitHub repositories, you can specify fully qualified
  references, e.g. starting with `refs/` to bypass the default search order.
+ When `-f`is provided, wipes the content of the target directory, unless the
  `UNGIT_KEEP` variable is set to `1`. Since `ungit` is about obtaining
  snapshots of target repositories, the (good) default prevents mixing several
  snapshots into the same target directory.
+ `-p` can prevent the target directory to be modified by forcing all files and
  sub-directories to be read-only. This can prevent heedless modification of the
  snapshots.
+ Can maintain an index of (relative) directories containing snapshots of added
  repositories. When using an index, target directory protection is
  automatically turned on.
+ When run from within a `git` repository, will automatically use a file called
  `.ungit` at the root of the repository as an index when adding the first time
  -- and unless specified otherwise.
+ `ungit` will automatically climb up the hierarchy starting from the
  destination directory to look for the `.ungit` index file when adding,
  installing or deleting. This means that while keeping the `.ungit` index file
  at the root of the git repository is the preferred way, you are free to choose
  differently.
+ `ungit` also works with private repositories as long as you can pass an
  authentication token with the `-T` option.

  [XDG]: https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html

## Limitations

+ If the target repository contains [submodules], the content of these
  submodules will not be part of the downloaded tarball, nor the directory
  snapshot.

## Why?

There are a number of scenarios where this can be useful:

+ When you want to have a quick look at the content of a project from the
  comfort of your favorite editor.
+ When you want to use neither [submodules], nor [subtree], but still want to
  use (and maintain over time) another project's tree within yours.
+ `ungit` implements a rudimentary package manager.
+ It was fun to write and only took a few hours.

  [submodules]: https://git-scm.com/book/en/v2/Git-Tools-Submodules
  [subtree]: https://git.kernel.org/pub/scm/git/git.git/plain/contrib/subtree/git-subtree.txt

## Speed

On a large repository, `ungit` is likely to be quicker because all `git`
operations are run within the remote's forge infrastructure (and file systems).
For example, the following timed `git` command:

```bash
time git clone -b v2.13.1 --depth 1 https://github.com/tensorflow/tensorflow.git
```

will output:

```console
real	0m33.170s
user	0m11.861s
sys	0m5.095s
```

While the following matching command, using `ungit` instead:

```bash
time ungit.sh tensorflow/tensorflow@v2.13.1
```

will output:

```console
real	0m18.650s
user	0m6.428s
sys	0m5.105s
```

When run as a GitHub action and against a repository at GitHub, the effect might
be the inverse. All the disk operations to create the compressed tarball and
unpack it on the receiving side will take extra time.
