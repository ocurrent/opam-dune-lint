open Types
open Dune_items

type t = Dir_set.t Libraries.t

let dune_describe_external_lib_deps = Bos.Cmd.(v "dune" % "describe" % "external-lib-deps")

let dune_describe_entries = Bos.Cmd.(v "dune" % "describe" % "package-entries")

let sexp cmd =
  Bos.OS.Cmd.run_out (cmd)
  |> Bos.OS.Cmd.to_string
  |> or_die
  |> String.trim
  |> (fun s ->
      try Sexp.of_string s with
      | Sexp.Parse_error _ as e -> Fmt.pr "Error parsing 'dune describe external-lib-deps' output:\n"; raise e)

let describe_external_lib_deps =
  sexp dune_describe_external_lib_deps
  |> Describe_external_lib.describe_extern_of_sexp

let describe_entries =
  sexp dune_describe_entries
  |> Describe_entries.entries_of_sexp

let has_dune_subproject = function
  | "." | "" -> false
  | dir -> Sys.file_exists (Filename.concat dir "dune-project")

let rec should_use_dir ~dir_types path =
  match Hashtbl.find_opt dir_types path with
  | Some x -> x
  | None ->
    let r =
      match Astring.String.cut ~sep:"/" ~rev:true path with
      | Some (parent, _) ->
        if should_use_dir ~dir_types parent then (
          not (has_dune_subproject path)
        ) else false
      | None ->
        not (has_dune_subproject path)
    in
    Hashtbl.add dir_types path r;
    r

let copy_rules =
  describe_external_lib_deps
  |> List.map Describe_external_lib.get_item
  |> List.map (fun (item:Describe_external_lib.item) -> String.cat item.source_dir "/dune")
  |> List.map (Dune_rules.Copy_rules.get_copy_rules)
  |> List.flatten
  |> Dune_rules.Copy_rules.copy_rules_map

let bin_of_entries = Describe_entries.items_bin_of_entries describe_entries

let find_exe_item_package (item:Describe_external_lib.item) =
  match item.package with
  | Some p -> Some p
  | None ->
    (* Only allow for private executables to find the package *)
    let bin_name =
      Dune_rules.Copy_rules.find_dest_name ~name:(String.cat item.name ".exe") copy_rules
    in
    Option.map (fun (item:Describe_entries.item) -> item.package) (Item_map.find_opt bin_name bin_of_entries)

let get_dune_items dir_types ~pkg ~target =
  let resolve_internal_deps d_items items_pkg =
    (* After the d_items are filtered to the corresponding package request,
     * we need to include the internal_deps in order to reach all the deps.
     * If the internal dep is a public library we skip the recursive resolve
     * because it will be resolve with separate request*)
    let open Describe_external_lib in
    let get_name = function
      | Lib item  -> String.cat item.name ".lib"
      | Exe item  -> String.cat item.name ".exe"
      | Test item -> String.cat item.name ".test"
    in
    let d_items_lib =
      d_items
      |> List.filter is_lib_item
      |> List.map get_item
      |> List.map (fun (item:Describe_external_lib.item) ->
          (String.cat item.name ".lib", Lib item))
      |> List.to_seq |> Hashtbl.of_seq
    in
    let rec add_internal acc = function
      | [] -> Hashtbl.to_seq_values acc |> List.of_seq
      | item::tl ->
        if Hashtbl.mem acc (get_name item) then
          add_internal acc tl
        else begin
          Hashtbl.add acc (get_name item) item;
          (get_item item).internal_deps
          |> List.filter (fun (_, k) -> Kind.is_required k)
          |> List.filter_map (fun (name, _) ->
              match Hashtbl.find_opt d_items_lib (String.cat name ".lib") with
              | None -> None
              | Some d_item_lib ->
                if Option.is_some (get_item d_item_lib).package then None else Some d_item_lib)
          |> fun internals -> add_internal acc (tl @ internals)
        end
    in
    add_internal (Hashtbl.create 10) items_pkg
  in
  describe_external_lib_deps
  |> List.map (fun d_item ->
      let item = Describe_external_lib.get_item d_item in
      if Describe_external_lib.is_exe_item d_item && Option.is_none item.package
      then
        match find_exe_item_package item  with
        | None ->  d_item
        | Some pkg -> Describe_external_lib.Exe { item with package = Some pkg }
      else d_item)
  |> List.filter (fun item ->
      match (item,target) with
      | Describe_external_lib.Test _, `Install -> false
      | Describe_external_lib.Test _, `Runtest -> true
      | _ , `Runtest -> false
      | _, `Install -> true)
  |> List.filter (fun d_item -> should_use_dir ~dir_types (Describe_external_lib.get_item d_item).source_dir)
  |> (fun d_items ->
      d_items
      |> List.filter (fun d_item ->
          let item = Describe_external_lib.get_item d_item in
          (* if an item has not package, we assume it's used for testing*)
          if target = `Install then
            Option.equal String.equal (Some pkg) item.package
          else
            Option.equal String.equal (Some pkg) item.package || Option.is_none item.package)
      |> resolve_internal_deps d_items)


let lib_deps ~pkg ~target =
  get_dune_items (Hashtbl.create 10) ~pkg ~target
  |> List.map Describe_external_lib.get_item
  |> List.fold_left (fun acc (item:Describe_external_lib.item) ->
      List.map (fun dep -> (fst dep, item.source_dir)) item.external_deps @ acc) []
  |> List.fold_left (fun acc (lib,path) ->
      if Astring.String.take ~sat:((<>) '.') lib <> pkg then
        let dirs = Libraries.find_opt lib acc |> Option.value ~default:Dir_set.empty in
        Libraries.add lib (Dir_set.add path dirs) acc
      else
        acc) Libraries.empty

let get_external_lib_deps ~pkg ~target : t = lib_deps ~pkg ~target
