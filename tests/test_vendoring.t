Create a project with vendored libraries.
`bin` depends on `lib` (an internal library).
`lib` depends on `vendored`.
We want to record the dependencies of `bin` and `lib` in the opam file, but not the dependencies of `vendored`,
since they should be listed in the vendored opam files instead.

  $ mkdir bin lib vendored

  $ cat > dune-project << EOF
  > (lang dune 2.7)
  > (generate_opam_files true)
  > (package
  >  (name main)
  >  (synopsis "Main package")
  >  (depends libfoo))
  > EOF

  $ cat > dune << EOF
  > (vendored_dirs vendored)
  > EOF

  $ cat > bin/dune << EOF
  > (executable
  >  (name main)
  >  (public_name main)
  >  (libraries lib))
  > EOF

  $ cat > lib/dune << EOF
  > (library
  >  (name lib)
  >  (libraries findlib vendored))
  > EOF

  $ cat > vendored/dune << EOF
  > (library
  >  (name vendored)
  >  (public_name vendored)
  >  (libraries bos))
  > EOF

  $ cat > vendored/dune-project << EOF
  > (lang dune 2.7)
  > EOF

  $ touch bin/main.ml lib/lib.ml
  $ (cd vendored && touch vendored.ml vendored.opam)
  $ dune build

Replace all version numbers with "1.0" to get predictable outut.

  $ export OPAM_DUNE_LINT_TESTS=y

Check configuration:

  $ dune external-lib-deps -p main @install
  These are the external library dependencies in the default context:
  - bos
  - findlib

Check that the missing findlib for "lib" is detected, but not "vendored"'s dependency
on "bos":

  $ opam-dune-lint </dev/null
  main.opam: changes needed:
    "ocamlfind" {>= 1.0}                     [from lib]
  Note: version numbers are just suggestions based on the currently installed version.
  Run with -f to apply changes in non-interactive mode.
  [1]
