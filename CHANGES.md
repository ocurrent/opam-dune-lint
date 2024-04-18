### v0.6

- Fix the issue #68, with Sexp format dune parse quoted string by escaping "%{" to become "\%{" that OpamFile module can't parse. So we switch to Csexp format which doesn't change quoted string (@moyodiallo #69).

- Fix the issue #66, when the content of dune-project file ends up with a comment, the Sexplib parse fails because the last `)` falls into the comment (@moyodiallo #67).

### v0.5

- Fix the lower bound to have 4.08.0 as the minimal version of OCaml (@moyodiallo #64).

- Fix the issue #61, Dune stanza `(generate_opam_files true)` is same as `(generate_opam_files)` stanza (@devvydeebug #62).

- Fix the issue #59, Sexplib parse fails because of Dune stanza description quote( `"\|` or `"\>`) (@moyodiallo #60).

### v0.4

- Fix the issue #53. Skip resolving a public library when it is added as optional dependency(dune's libraries stanza) (@moyodiallo #54).

- Print all the errors before the exit (@moyodiallo #55).

### v0.3

- Fix the issue #51, when there's no package declared in `dune-project` file (@moyodiallo #52).

- Add support for dune 3.0 , the command `dune external-lib-deps` was removed from
  dune. Now, the `opam-dune-lint` command works without `dune build`. (@moyodiallo #46).

### v0.2

- Cope with missing `(depends ...)` in `dune-project` (@talex5 #33). We tried to add the missing packages to an existing depends field, but if there wasn't one at all then we did nothing.

- Use quoted versions in the fix suggestion string (@tmcgilchrist #32). Makes copy-and-paste easier for people using it via a web UI.

- Support older versions of OCaml back to 4.10 (@tmcgilchrist #31).

- Ignore dependencies on sub-packages (@dra27 #27). Library `foo` may depend on library `foo.bar` but this cannot introduce an opam dependency on `foo` in `foo.opam`.

- Require opam libraries compatible with the client (@dra27 #26).

- Add support for multiple dependency clauses for the same package (@kit-ty-kate #25).

- Upgrade to dune-private-libs 2.8.0 (@kit-ty-kate #20).

- Remove dependency on ocamlfind, as we don't use it for anything now (@talex5 #18).

### v0.1

Initial release.
