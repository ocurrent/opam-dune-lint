This is a test inspired when testing opam-dune-lint against
dune project "https://github.com/ocaml/dune/". There is 2 executables
with the same name in different directory. The public executable was also
taking the deps from the private library.

  $ mkdir bin bench
  $ cat > dune-project << EOF
  > (lang dune 2.7)
  > (generate_opam_files true)
  > (package
  >  (name test)
  >  (synopsis "Test package")
  >  (depends
  >   (ocamlfind (>= 1.0))
  >   libfoo))
  > EOF

  $ cat > bench/dune << EOF
  > (executable
  >  (name main)
  >  (modules main)
  >  (libraries sexplib cmdliner))
  > EOF

  $ cat > bin/dune << EOF
  > (executable
  >  (name main)
  >  (public_name main)
  >  (modules main)
  >  (libraries findlib fmt))
  > (test
  >  (name test)
  >  (modules test)
  >  (libraries bos opam-state))
  > EOF

  $ touch bin/main.ml bin/test.ml bench/main.ml
  $ dune build

  $ export OPAM_DUNE_LINT_TESTS=y

Check that the missing libraries are detected:

  $ opam-dune-lint </dev/null
  test.opam: changes needed:
    "fmt" {>= "1.0"}                         [from bin]
    "bos" {with-test & >= "1.0"}             [from bin]
    "opam-state" {with-test & >= "1.0"}      [from bin]
  Note: version numbers are just suggestions based on the currently installed version.
  Run with -f to apply changes in non-interactive mode.
  [1]

Check that the missing libraries get added:

  $ opam-dune-lint -f
  test.opam: changes needed:
    "fmt" {>= "1.0"}                         [from bin]
    "bos" {with-test & >= "1.0"}             [from bin]
    "opam-state" {with-test & >= "1.0"}      [from bin]
  Note: version numbers are just suggestions based on the currently installed version.
  Wrote "dune-project"
