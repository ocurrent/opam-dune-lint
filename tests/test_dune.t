Create a simple dune project:

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

Check that the missing libraries are detected:

  $ opam-dune-lint </dev/null
  test.opam: changes needed:
    "fmt" {>= 1.0}
    "bos" {with-test & >= 1.0}
    "opam-state" {with-test & >= 1.0}
  Run with -f to apply changes in non-interactive mode.
  [1]

Check that the missing libraries get added:

  $ opam-dune-lint -f
  test.opam: changes needed:
    "fmt" {>= 1.0}
    "bos" {with-test & >= 1.0}
    "opam-state" {with-test & >= 1.0}
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
    (fmt (>= *))
    (ocamlfind (>= *))
    libfoo))

Check adding and removing of test markers:

  $ cat > dune-project << EOF
  > (lang dune 2.7)
  > (generate_opam_files true)
  > (package
  >  (name test)
  >  (synopsis "Test package")
  >  (depends
  >   opam-state
  >   (bos (>= 1.0))
  >   (fmt :with-test)
  >   (ocamlfind (and (>= 1.0) :with-test))
  >   libfoo))
  > EOF

  $ dune build @install

  $ opam-dune-lint -f
  test.opam: changes needed:
    "fmt"                          (remove {with-test})
    "ocamlfind"                    (remove {with-test})
    "bos" {with-test}              (missing {with-test} annotation)
    "opam-state" {with-test}       (missing {with-test} annotation)
  Wrote "dune-project"

  $ cat dune-project | sed 's/= [^)}]*/= */g'
  (lang dune 2.7)
  (generate_opam_files true)
  (package
   (name test)
   (synopsis "Test package")
   (depends
    (opam-state :with-test)
    (bos (and :with-test (>= *)))
    fmt
    (ocamlfind (>= *))
    libfoo))

  $ opam-dune-lint
  test.opam: OK
