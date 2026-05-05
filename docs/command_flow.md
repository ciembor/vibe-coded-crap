# Command Flow

The executable loads `Helpdesk::CLI` and calls `run`.

`Helpdesk::CLI#run` owns terminal I/O:

1. Read one line from `STDIN`.
2. Parse it with `Shellwords.split`.
3. Resolve any configured alias.
4. Ask `Helpdesk::CliCommandRouter` to dispatch built-in commands.
5. Fall back to plugin commands when the router returns `:unknown`.
6. Print an unknown-command message if no plugin handles the command.

`Helpdesk::CliCommandRouter` owns only routing. It returns:

- `:handled` after a built-in command handler runs.
- `:exit` for exit commands.
- `:unknown` when no route matches.

Command methods remain private on `Helpdesk::CLI`. The router may invoke them, but callers outside the CLI should use the `run` loop or domain/store objects instead of calling command methods directly.
