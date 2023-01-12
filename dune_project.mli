open Types

type t

val parse : unit -> t
(** [parse ()] loads the "dune-project" file. *)

val generate_opam_enabled : t -> bool
(** Check whether (generate_opam_files true) is present. *)

val update : (_ * Change.t list) Paths.t -> t -> t

val write_project_file : t -> unit

type index

val describe : unit -> index
(** Create an index of the project's libraries, using "dune describe". *)

val lookup : string -> index -> [`Internal | `External] option
(** [lookup lib index] returns information from "dune describe" about [lib]. *)

module Deps : sig
  type t = Dir_set.t Libraries.t
  (** The set of OCamlfind libraries needed, each with the directories needing it. *)

  val get_external_lib_deps : pkg:string -> target:[`Install | `Runtest] -> t
end
