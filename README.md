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

`opam-dune-lint` can be run manually to update your project, or as part of CI to check for missing dependencies.
It exits with a non-zero status if changes are needed, or if the opam files were not up-to-date with the `dune-project` file.
When run interactively, it asks for confirmation before writing files.
If `stdin` is not a tty, then it does not write changes unless run with `-f`.
