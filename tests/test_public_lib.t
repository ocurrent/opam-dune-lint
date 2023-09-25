Create a simple dune project and test when a public library as internal dep is not recursively resolved:

  $ cat > dune-project << EOF
  > (lang dune 2.7)
  > (generate_opam_files true)
  > (package
  >  (name test)
  >  (synopsis "Test package")
  >  (depends
  >   (ocamlfind (>= 1.0))
  >   libfoo))
  > (package
  >  (name lib)
  >  (synopsis "Lib package")
  >  (depends sexplib))
  > EOF

  $ cat > dune << EOF
  > (library
  >  (public_name lib)
  >  (modules lib)
  >  (libraries sexplib))
  > (executable
  >  (name main)
  >  (modules main)
  >  (libraries lib findlib fmt))
  > (test
  >  (name test)
  >  (modules test)
  >  (libraries lib bos opam-state))
  > (install
  >  (section bin)
  >  (package test)
  >  (files main.exe))
  > EOF

  $ touch main.ml test.ml lib.ml
  $ dune build

  $ export OPAM_DUNE_LINT_TESTS=y

Check that the missing libraries are detected:

  $ opam-dune-lint </dev/null
  lib.opam: changes needed:
    "bos" {with-test & >= "1.0"}             [from /]
    "opam-state" {with-test & >= "1.0"}      [from /]
  test.opam: changes needed:
    "fmt" {>= "1.0"}                         [from /]
    "bos" {with-test & >= "1.0"}             [from /]
    "opam-state" {with-test & >= "1.0"}      [from /]
  Note: version numbers are just suggestions based on the currently installed version.
  Run with -f to apply changes in non-interactive mode.
  [1]

Check that the missing libraries get added:

  $ opam-dune-lint -f
  lib.opam: changes needed:
    "bos" {with-test & >= "1.0"}             [from /]
    "opam-state" {with-test & >= "1.0"}      [from /]
  test.opam: changes needed:
    "fmt" {>= "1.0"}                         [from /]
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
    (opam-state
     (and
      (>= *)
      :with-test))
    (bos
     (and
      (>= *)
      :with-test))
    (fmt
     (>= *))
    (ocamlfind
     (>= *))
    libfoo))
  
  (package
   (name lib)
   (synopsis "Lib package")
   (depends
    (opam-state
     (and
      (>= *)
      :with-test))
    (bos
     (and
      (>= *)
      :with-test))
    sexplib))

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
  > (package
  >  (name lib)
  >  (synopsis "Lib package")
  >  (depends sexplib))
  > EOF

  $ dune build @install

  $ opam-dune-lint -f
  lib.opam: changes needed:
    "bos" {with-test & >= "1.0"}             [from /]
    "opam-state" {with-test & >= "1.0"}      [from /]
  test.opam: changes needed:
    "fmt"                                    [from /] (remove {with-test})
    "ocamlfind"                              [from /] (remove {with-test})
    "bos" {with-test}                        [from /] (missing {with-test} annotation)
    "opam-state" {with-test}                 [from /] (missing {with-test} annotation)
  Note: version numbers are just suggestions based on the currently installed version.
  Wrote "dune-project"

  $ cat dune-project | sed 's/= [^)}]*/= */g'
  (lang dune 2.7)
  
  (generate_opam_files true)
  
  (package
   (name test)
   (synopsis "Test package")
   (depends
    (opam-state :with-test)
    (bos
     (and
      :with-test
      (>= *)))
    fmt
    (ocamlfind
     (>= *))
    libfoo))
  
  (package
   (name lib)
   (synopsis "Lib package")
   (depends
    (opam-state
     (and
      (>= *)
      :with-test))
    (bos
     (and
      (>= *)
      :with-test))
    sexplib))

  $ opam-dune-lint
  lib.opam: OK
  test.opam: OK
