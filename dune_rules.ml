open Types

module Copy_rules = struct

  let sexp_of_file file =
    try Sexp.load_sexps @@ Fpath.to_string file with
    | Sexp.Parse_error _ as e ->
      (Fmt.pr "Error parsing 'dune file' output:\n"; raise e)

  type t =
    {
      target: string;
      from_name: string;
      to_name: string;
      dep: string;
      package: string
    }

  let dump_copy = {
    target = "";
    from_name = "";
    to_name = "";
    dep = "";
    package = ""
  }

  let rules = Hashtbl.create 10

  let copy_rules_of_sexp sexps =
    let is_action_copy sexp =
      sexp
      |> (function
          | Sexp.List l -> if List.mem (Sexp.Atom "rule") l then l else []
          | _ -> [])
      |> List.exists (function
          | Sexp.List [ Atom "action"; List [ Atom "copy"; _; _]] -> true
          | _ -> false)
    in
    let copy_rule_of_sexp sexp =
      match sexp with
      | Sexp.List sexps ->
        List.fold_left (fun copy _sexp ->
            match _sexp with
            | Sexp.List [Atom "action"; List [ _; Atom f; Atom t]] ->
              {{copy with from_name = f } with to_name = t}
            | Sexp.List [Atom "deps"; List [Atom "package"; Atom s]]-> {copy with package = s}
            | Sexp.List [Atom "deps"; List [Atom "package"; Atom p]; Atom d]
            | Sexp.List [Atom "deps"; Atom d; List [Atom "package"; Atom p]] ->
              {{copy with package = p} with dep = d}
            | Sexp.List [Atom "deps"; Atom s]    -> {copy with dep = s}
            | Sexp.List [Atom "target"; Atom s]  -> {copy with target = s}
            | Sexp.Atom "rule"                   -> copy
            | _ -> copy
          ) dump_copy sexps
      | s -> Fmt.failwith "%s is not a rule" (Sexp.to_string s)
    in
    sexps
    |> List.filter_map (fun rule ->
        if not (is_action_copy rule) then
          None
        else
          rule
          |> copy_rule_of_sexp
          |> fun copy ->
          if String.equal copy.to_name "%{target}" && String.equal copy.from_name "%{deps}" then
            (*when we got `(action (copy %{deps} %{target}))` *)
            Some {{copy with to_name = copy.target} with from_name = copy.dep}
          else Some copy)

  let copy_rules_map =
    List.fold_left (fun map copy -> Item_map.add copy.from_name copy map) Item_map.empty

  let get_copy_rules file =
    match Hashtbl.find_opt rules file with
    | None when OS.Path.exists file |> Stdlib.Result.get_ok ->
      let copy_rules = copy_rules_of_sexp (sexp_of_file file) in
      Hashtbl.add rules file copy_rules; copy_rules
    | None -> Hashtbl.add rules file []; []
    | Some copy_rules -> copy_rules

  let find_dest_name ~name rules =
    let rec find_dest_name name rules =
      match Item_map.find_opt name rules with
      | None   -> Some name
      | Some t -> find_dest_name t.to_name rules
    in
    match Item_map.find_opt name rules with
    | None -> None (* Not found in the first step *)
    | Some t -> find_dest_name t.to_name rules
end
