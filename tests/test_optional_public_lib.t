Inspired from test_vendoring.t test. Create a project with an public optional libraries
It fixes the bug #53. The fix is about to not resolve an public optional library when used as dependency.

  $ mkdir bin lib optional

  $ cat > dune-project << EOF
  > (lang dune 2.7)
  > (generate_opam_files true)
  > (package
  >  (name main)
  >  (synopsis "Main package")
  >  (depends libfoo))
  > (package
  >  (name optional)
  >  (synopsis "Optional package")
  >  (depends bos))
  > EOF

  $ cat > bin/dune << EOF
  > (executable
  >  (name main)
  >  (package main)
  >  (public_name main)
  >  (libraries lib))
  > EOF

  $ cat > lib/dune << EOF
  > (library
  >  (name lib)
  >  (public_name main)
  >  (libraries findlib 
  >   (select file.ml from
  >    (optional -> file.enabled.ml)
  >    (         -> file.disabled.ml))))
  > EOF

  $ cat > optional/dune << EOF
  > (library
  >  (name optinal)
  >  (public_name optional)
  >  (libraries bos))
  > EOF

  $ touch bin/main.ml lib/lib.ml lib/file.disabled.ml lib/file.enabled.ml optional/optional.ml
  $ dune build

Replace all version numbers with "1.0" to get predictable outut.

  $ export OPAM_DUNE_LINT_TESTS=y

Check configuration:

  $ dune external-lib-deps -p main @install
  dune: This subcommand has been moved to dune describe external-lib-deps.
  [1]

Check that the missing findlib for "lib" is detected, but not "optional"'s dependency
on "bos":

  $ opam-dune-lint </dev/null
  main.opam: changes needed:
    "ocamlfind" {>= "1.0"}                   [from lib]
  optional.opam: OK
  Note: version numbers are just suggestions based on the currently installed version.
  Run with -f to apply changes in non-interactive mode.
  [1]
