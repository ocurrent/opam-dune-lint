Create a dune project with no depends section:

  $ cat > dune-project << EOF
  > (lang dune 2.7)
  > (generate_opam_files true)
  > (package
  >  (name test)
  >  (synopsis "Test package"))
  > EOF

  $ cat > dune << EOF
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

  $ touch main.ml test.ml
  $ dune build

Replace all version numbers with "1.0" to get predictable outut.

  $ export OPAM_DUNE_LINT_TESTS=y

Check that all the libraries get added:

  $ opam-dune-lint -f
  test.opam: changes needed:
    "fmt" {>= "1.0"}                         [from /]
    "ocamlfind" {>= "1.0"}                   [from /]
    "bos" {with-test & >= "1.0"}             [from /]
    "opam-state" {with-test & >= "1.0"}      [from /]
  Note: version numbers are just suggestions based on the currently installed version.
  Wrote "dune-project"

  $ cat dune-project | sed 's/= [^)}]*/= */g'
  (lang dune 2.7)
  (generate_opam_files true)
  (package
   (name test)
   (synopsis "Test package")
   (depends
    (opam-state (and (>= *) :with-test))
    (bos (and (>= *) :with-test))
    (ocamlfind (>= *))
    (fmt (>= *))))
