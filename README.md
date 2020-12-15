# opam-dune-lint

`opam-dune-lint` checks that all ocamlfind libraries listed as dune
dependencies have corresponding opam dependencies listed in the opam files.
If not, it offers to add them (either to your opam files, or to your `dune-project` if you're generating your opam files from that).

Example:

```
$ ls *.opam
ocaml-ci-api.opam     ocaml-ci-service.opam  ocaml-ci-web.opam
ocaml-ci-client.opam  ocaml-ci-solver.opam

$ opam-dune-lint
ocaml-ci-api.opam: OK
ocaml-ci-client.opam: OK
ocaml-ci-service.opam: changes needed:
  "fmt" {>= 0.8.9}
  "alcotest-lwt" {with-test & >= 1.2.3}
ocaml-ci-solver.opam: OK
ocaml-ci-web.opam: OK
Write changes? [y] y
Wrote "dune-project"
```

It works as follows:

1. Lists the `*.opam` files in your project's root (ensuring they're up-to-date, if generated).
2. Runs `dune external-lib-deps --only-packages $PKG --unstable-by-dir @install` and `... @runtest` to get each package's ocamlfind dependencies.
3. Filters out local dependencies using `dune describe` (for now; would be good to lint these too in future, but needs a different code path).
4. Filters out vendored dependencies (by ignoring dependencies from subdirectories with their own `dune-project` file).
5. For each ocamlfind library, it finds the corresponding opam library by
   finding its directory and then finding the `*.changes` file saying which
   opam package added its `META` file.
6. Checks that each required opam package is listed in the opam file.
7. For any missing packages, it offers to add a suitable dependency, using the installed package's version as the default lower-bound.

`opam-dune-lint` can be run manually to update your project, or as part of CI to check for missing dependencies.
It exits with a non-zero status if changes are needed, or if the opam files were not up-to-date with the `dune-project` file.
When run interactively, it asks for confirmation before writing files.
If `stdin` is not a tty, then it does not write changes unless run with `-f`.
