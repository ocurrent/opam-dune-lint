Libraries distributed with the OxCaml compiler need no opam dependency.
They are not installed with mainstream OCaml, so use them in a disabled
stanza (dune describe external-lib-deps lists it anyway):

  $ cat > dune-project << EOF
  > (lang dune 2.7)
  > (generate_opam_files true)
  > (package
  >  (name test)
  >  (synopsis "Test package"))
  > EOF

  $ cat > dune << EOF
  > (test
  >  (name test)
  >  (enabled_if false)
  >  (libraries stdlib_stable stdlib_upstream_compatible stdlib_alpha stdlib_beta))
  > EOF

  $ touch test.ml
  $ dune build

  $ export OPAM_DUNE_LINT_TESTS=y

  $ opam-dune-lint
  test.opam: OK
