import argv
import gleam/io
import gleam/result
import gleam_toml_manager/app_error.{type AppError}
import gleam_toml_manager/commands
import glint
import shellout
import simplifile
import tomlet

pub fn main() {
  glint.new()
  |> glint.with_name("gleam_toml_manager")
  |> glint.pretty_help(glint.default_pretty_help())
  |> glint.global_help(
    "Manage a gleam.toml while preserving comments and key order",
  )
  |> glint.add(at: ["bump"], do: bump_command())
  |> glint.add(at: ["add-dep"], do: add_dep_command())
  |> glint.add(at: ["remove-dep"], do: remove_dep_command())
  |> glint.add(at: ["get"], do: get_command())
  |> glint.add(at: ["set"], do: set_command())
  |> glint.run(argv.load().arguments)
}

// --- shared flags -----------------------------------------------------------

fn file_flag() -> glint.Flag(String) {
  glint.string_flag("file")
  |> glint.flag_default("gleam.toml")
  |> glint.flag_help("Path to the TOML file (default: gleam.toml)")
}

fn dry_run_flag() -> glint.Flag(Bool) {
  glint.bool_flag("dry-run")
  |> glint.flag_default(False)
  |> glint.flag_help("Print the result to stdout instead of writing the file")
}

// --- commands ---------------------------------------------------------------

fn bump_command() -> glint.Command(Nil) {
  use <- glint.command_help("Bump the version: bump <major|minor|patch>")
  use file <- glint.flag(file_flag())
  use dry_run <- glint.flag(dry_run_flag())
  use part <- glint.named_arg("part")
  use named, _args, flags <- glint.command()
  let assert Ok(path) = file(flags)
  let assert Ok(dry) = dry_run(flags)
  let part_text = part(named)
  run_edit(path, dry, fn(doc) { commands.bump(doc, part_text) })
}

fn add_dep_command() -> glint.Command(Nil) {
  use <- glint.command_help(
    "Add or update a dependency: add-dep <name> <version>",
  )
  use file <- glint.flag(file_flag())
  use dry_run <- glint.flag(dry_run_flag())
  use name <- glint.named_arg("name")
  use version <- glint.named_arg("version")
  use named, _args, flags <- glint.command()
  let assert Ok(path) = file(flags)
  let assert Ok(dry) = dry_run(flags)
  let dep_name = name(named)
  let dep_version = version(named)
  run_edit(path, dry, fn(doc) {
    commands.add_dependency(doc, dep_name, dep_version)
  })
}

fn remove_dep_command() -> glint.Command(Nil) {
  use <- glint.command_help("Remove a dependency: remove-dep <name>")
  use file <- glint.flag(file_flag())
  use dry_run <- glint.flag(dry_run_flag())
  use name <- glint.named_arg("name")
  use named, _args, flags <- glint.command()
  let assert Ok(path) = file(flags)
  let assert Ok(dry) = dry_run(flags)
  let dep_name = name(named)
  run_edit(path, dry, fn(doc) { commands.remove_dependency(doc, dep_name) })
}

fn get_command() -> glint.Command(Nil) {
  use <- glint.command_help("Read a value at a dotted path: get <a.b.c>")
  use file <- glint.flag(file_flag())
  use path_arg <- glint.named_arg("path")
  use named, _args, flags <- glint.command()
  let assert Ok(path) = file(flags)
  let dotted = path_arg(named)
  let outcome = {
    use source <- result.try(read_file(path))
    use doc <- result.try(parse_doc(source))
    commands.get_path(doc, dotted)
  }
  case outcome {
    Ok(value) -> io.println(commands.value_to_display(value))
    Error(error) -> fail(error)
  }
}

fn set_command() -> glint.Command(Nil) {
  use <- glint.command_help(
    "Set a string value at a dotted path: set <a.b.c> <value>",
  )
  use file <- glint.flag(file_flag())
  use dry_run <- glint.flag(dry_run_flag())
  use path_arg <- glint.named_arg("path")
  use value_arg <- glint.named_arg("value")
  use named, _args, flags <- glint.command()
  let assert Ok(path) = file(flags)
  let assert Ok(dry) = dry_run(flags)
  let dotted = path_arg(named)
  let new_value = value_arg(named)
  run_edit(path, dry, fn(doc) { commands.set_path(doc, dotted, new_value) })
}

// --- IO + edit pipeline -----------------------------------------------------

fn run_edit(
  path: String,
  dry_run: Bool,
  edit: fn(tomlet.Document) -> Result(tomlet.Document, AppError),
) -> Nil {
  let outcome = {
    use source <- result.try(read_file(path))
    use doc <- result.try(parse_doc(source))
    use edited <- result.try(edit(doc))
    Ok(tomlet.to_string(edited))
  }
  case outcome {
    Error(error) -> fail(error)
    Ok(text) ->
      case dry_run {
        True -> io.println(text)
        False ->
          case write_file(path, text) {
            Ok(Nil) -> io.println("updated " <> path)
            Error(error) -> fail(error)
          }
      }
  }
}

fn read_file(path: String) -> Result(String, AppError) {
  simplifile.read(from: path)
  |> result.map_error(app_error.FileError)
}

fn write_file(path: String, contents: String) -> Result(Nil, AppError) {
  simplifile.write(to: path, contents: contents)
  |> result.map_error(app_error.FileError)
}

fn parse_doc(source: String) -> Result(tomlet.Document, AppError) {
  tomlet.parse(source)
  |> result.map_error(fn(error) { app_error.ParseError(error, source) })
}

/// Print the error to stderr and terminate with a non-zero status. `shellout.exit`
/// sets the process exit code on both the Erlang and JavaScript targets, so the
/// CLI is usable in pipelines and CI. Successful command paths return `Nil` and
/// let the runtime exit `0` normally.
fn fail(error: AppError) -> Nil {
  io.println_error(app_error.to_message(error))
  shellout.exit(1)
}
