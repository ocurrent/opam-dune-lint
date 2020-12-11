(lang dune 2.7)
(name dune-opam-lint)
(formatting disabled)
(generate_opam_files true)
(source (github talex5/dune-opam-lint))
(authors "talex5@gmail.com")
(maintainers "talex5@gmail.com")
(cram enable)
(package
 (name dune-opam-lint)
 (synopsis "Ensure dune and opam dependencies are consistent")
 (depends
  (cmdliner (>= 1.0.4))
  (dune-private-libs (>= 2.7.1))
  (ocaml (>= 4.11.0))
  ocamlfind
  bos
  fmt
  opam-state
  opam-format))
