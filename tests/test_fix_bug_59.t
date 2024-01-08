Sexplib fails to parse `"\>` or `"\|`, those are finely parsed by dune. (issue #59) 
opam-dune-lint does not need the description section.

  $ cat > dune-project << EOF
  > (lang dune 2.7)
  > (generate_opam_files)
  > (name dummy)
  > 
  > (package
  >  (name dummy)
  >  (description
  >   "\> Dummy
  >   ))
  > EOF

  $ dune build
  $ opam-dune-lint -f 
  dummy.opam: OK

  $ cat > dune-project << EOF
  > (lang dune 2.7)
  > (generate_opam_files)
  > (name dummy)
  > 
  > (package
  >  (name dummy)
  >  (description
  >   "\> Dummy
  >   "\| Dummy other
  >   ))
  > EOF

  $ dune build
  $ opam-dune-lint -f 
  dummy.opam: OK

  $ cat > dune-project << EOF
  > (lang dune 2.7)
  > (generate_opam_files)
  > (name dummy)
  > 
  > (package
  >  (name dummy)
  >  (description
  >   "\> Dummy
  >   "\| Dummy other
  >   "\> Dummy other
  >   ))
  > EOF

  $ dune build
  $ opam-dune-lint -f 
  dummy.opam: OK
