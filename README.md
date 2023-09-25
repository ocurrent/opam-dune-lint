# opam-dune-lint

`opam-dune-lint` checks that all ocamlfind libraries listed as dune
dependencies have corresponding opam dependencies listed in the opam files.
If not, it offers to add them (either to your opam files, or to your `dune-project` if you're generating your opam files from that).

Example:

```
$ ls *.opam
current_ocluster.opam  ocluster-api.opam  ocluster.opam

$ opam-dune-lint
current_ocluster.opam: changes needed:
  "ppx_deriving" {>= 5.1}                  [from (ppx), ocurrent-plugin]
ocluster-api.opam: changes needed:
  "ppx_deriving" {>= 5.1}                  [from (ppx), api]
ocluster.opam: changes needed:
  "capnp-rpc-lwt" {>= 0.8.0}               [from scheduler, worker]
  "capnp-rpc-net" {>= 0.8.0}               [from scheduler]
  "ppx_sexp_conv" {>= v0.14.1}             [from (ppx)]
  "prometheus" {>= 0.7}                    [from scheduler]
  "alcotest-lwt" {with-test}               [from test] (missing {with-test} annotation)
Note: version numbers are just suggestions based on the currently installed version.
Write changes? [y] y
Wrote "dune-project"
```

It works as follows:

1. Lists the `*.opam` files in your project's root (ensuring they're up-to-date, if generated).
2. Runs `dune describe external-lib-deps` to get all externals and internals ocamlfind libraries for all dune libraries, executables and tests. The information about the package is also known except for the private executables.
3. Runs `dune describe package-entries` to get all packages entries, this is for considering the external ocamlfind libraries of a private executable, because in Dune it is possible to install a private executable.
4. Resolve for each opam library its internal and external ocamlfind library dependencies using the information of 1. and 2.
5. Filters out vendored dependencies (by ignoring dependencies from subdirectories with their own `dune-project` file).
6. For each ocamlfind library, it finds the corresponding opam library by
   finding its directory and then finding the `*.changes` file saying which
   opam package added its `META` file.
7. Checks that each required opam package is listed in the opam file.
8. For any missing packages, it offers to add a suitable dependency, using the installed package's version as the default lower-bound.

`opam-dune-lint` can be run manually to update your project, or as part of CI to check for missing dependencies.
It exits with a non-zero status if changes are needed, or if the opam files were not up-to-date with the `dune-project` file.
When run interactively, it asks for confirmation before writing files.
If `stdin` is not a tty, then it does not write changes unless run with `-f`.
