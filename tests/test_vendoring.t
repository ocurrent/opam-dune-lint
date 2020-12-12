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

Check configuration:

  $ dune external-lib-deps -p main @install
  These are the external library dependencies in the default context:
  - bos
  - findlib

Check that the missing findlib for "lib" is detected, but not "vendored"'s dependency
on "bos":

  $ dune-opam-lint </dev/null 2>&1 | sed 's/= [^)}]*/= */g'
  main.opam: changes needed:
    "ocamlfind" {>= *}
  Run with -f to apply changes in non-interactive mode.
