opam-dune-lint is using a kind of hack to parse `dune-project` string,
wrapping it up as "(__dune_project";`dune_project_file_string`;")" S-expression. When
`dune_project_file_string` ends up with a comment, the ")" fall into the last comment itself.

  $ cat > dune-project << EOF
  > (lang dune 2.7)
  > (generate_opam_files)
  > ; comment added at end
  > EOF

  $ cat > empty.opam << EOF
  > opam-version: "2.0"
  > EOF

  $ touch dune
  $ opam-dune-lint
  empty.opam: changed after its upgrade from 'dune describe opam-files'!
  empty.opam: OK
  Warning in empty: The package has a dune-project file but no explicit dependency on dune was found.
  [1]
