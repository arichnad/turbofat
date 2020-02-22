# turbofat
Block-dropping puzzle game

# Building

* godot 3.2+ is required.

* start the godot UI and click Editor -> Manage Export Templates

* click on Download next to one of the templates.

* after the download completes, you can do an export in Project -> Export to export a project.

* (you can also build from the command line:  `godot project.godot --export "Windows Desktop" "Turbo Fat.exe"`

on linux:  `godot project.godot --export "Linux/X11" turbofat`)

# Glossary

Here's a glossary of terms used within the code. When editing code, try to use consistent terms like "each cubit" instead of "each piece", or "whenever the player sees" instead of "whenever you see"

**box:** a 3x3, 3x4 or 3x5 rectangle built from intact pieces.

**block:** a solid element occupying one cell of the playfield.

**cell:** a unit square within the playfield.

**line:** a horizontal row of blocks.

**piece:** a set of blocks that moves as a unit. 

**player:** the person playing the game.

**playfield:** the grid of cells into which pieces are placed. 
