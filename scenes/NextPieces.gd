"""
Contains logic for displaying upcoming pieces to the player, organizing and maintaining all of the 'next piece
displays'.
"""
extends Node2D

export (PackedScene) var NextPieceDisplay
onready var PieceTypes = preload("res://scenes/PieceTypes.gd").new()

# Queue of upcoming randomized pieces. The first few pieces are displayed to the player
var next_pieces = []

# The "next piece displays" which are shown to the user
var next_piece_displays = []

func _ready():
	# Ensure pieces are random
	randomize()
	fill_queue()
	
	# The main "next piece display" is full size
	add_display(0)
	
	# There are many other smaller displays to the size
	add_display(1,  96,  0, 0.5)
	add_display(2, 164,  0, 0.5)
	add_display(3, 180, 64, 0.5)
	add_display(4, 180, 128, 0.5)
	add_display(5, 180, 192, 0.5)

"""
Hides all next piece displays. We can't let the player see the upcoming pieces before the game starts.
"""
func hide_pieces():
	for next_piece_display in next_piece_displays:
		next_piece_display.hide()

"""
Starts a new game, randomizing the pieces and filling the piece queues.
"""
func start_game():
	next_pieces.clear()
	fill_queue()
	
	for next_piece_display in next_piece_displays:
		next_piece_display.show()

"""
Adds a new 'next piece display'.
"""
func add_display(piece_index, x = 0, y = 0, scale = 1):
	var new_display = NextPieceDisplay.instance()
	new_display.piece_index = piece_index
	new_display.scale = Vector2(scale, scale)
	new_display.position = Vector2(x + (48 - 48 * scale), y + (48 - 48 * scale))
	add_child(new_display)
	next_piece_displays.append(new_display)

"""
Pops the next piece off the queue.
"""
func pop_piece_type():
	var next_piece_type = next_pieces.pop_front()
	fill_queue()
	return next_piece_type

"""
This method fills the queue of upcoming pieces with newly randomized pieces, following a specific algorithm.

During the game, the random algorithm works as follows: All 8 pieces are randomly thrown into a bag with 1 random
piece. They’re shuffled fairly, but you’re guaranteed to never pull the same piece twice-in-a-row. This makes it so
that you're always able to make four simple 3x3 boxes, but sometimes the extra piece is a pain in the ass. This
prevents the game from being too simple.

Initially, the random algorithm works a little differently: The game comes up with the five pieces necessary to make a
small and large box and shuffles them. This undermines the simple strategy of starting every game by making 4 3x3
boxes.
"""
func fill_queue():
	if next_pieces.empty():
		# calculate five pieces which can make a 3x3 and either a 3x4 or 3x5
		var all_threes = [
			[PieceTypes.piece_j, PieceTypes.piece_p],
			[PieceTypes.piece_l, PieceTypes.piece_q],
			[PieceTypes.piece_o, PieceTypes.piece_v],
			[PieceTypes.piece_t, PieceTypes.piece_u]
		]
		next_pieces += all_threes[randi() % all_threes.size()]
		if (randf() > 0.5):
			var all_quads = [
				[PieceTypes.piece_j, PieceTypes.piece_t, PieceTypes.piece_t],
				[PieceTypes.piece_l, PieceTypes.piece_t, PieceTypes.piece_t],
				[PieceTypes.piece_j, PieceTypes.piece_j, PieceTypes.piece_o],
				[PieceTypes.piece_l, PieceTypes.piece_l, PieceTypes.piece_o],
				[PieceTypes.piece_j, PieceTypes.piece_l, PieceTypes.piece_o]
			]
			next_pieces += all_quads[randi() % all_quads.size()]
		else:
			var all_pentos = [
				[PieceTypes.piece_p, PieceTypes.piece_u, PieceTypes.piece_v],
				[PieceTypes.piece_q, PieceTypes.piece_u, PieceTypes.piece_v],
				[PieceTypes.piece_p, PieceTypes.piece_q, PieceTypes.piece_v]
			]
			next_pieces += all_pentos[randi() % all_pentos.size()]
		
		# shuffle the five pieces until the same piece doesn't appear twice-in-a-row
		for mercy in range (0, 1000):
			next_pieces.shuffle()
			var no_touching_pieces = true
			for from_index in range(0, next_pieces.size() - 1):
				if next_pieces[from_index] == next_pieces[from_index + 1]:
					no_touching_pieces = false
			if no_touching_pieces:
				break
	
	while next_pieces.size() < 50:
		# fill a bag with one of each piece and one extra; draw them out in a random order, ensuring we never see two
		# of the same piece in a row
		var new_pieces = PieceTypes.all_types.duplicate()
		new_pieces.shuffle()
		
		# avoid having two of the same piece consecutively
		if new_pieces[0] == next_pieces.back():
			new_pieces.pop_front()
			new_pieces.insert(int(rand_range(1, new_pieces.size() + 1)), next_pieces.back())
		
		# add one extra piece
		var new_piece_index = int(rand_range(1, new_pieces.size() + 1))
		var extra_piece_types = PieceTypes.all_types.duplicate()
		extra_piece_types.remove(extra_piece_types.rfind(new_pieces[new_piece_index - 1]))
		if (new_piece_index < new_pieces.size()):
			extra_piece_types.remove(extra_piece_types.rfind(new_pieces[new_piece_index]))
		new_pieces.insert(new_piece_index, extra_piece_types[randi() % extra_piece_types.size()])
		
		next_pieces += new_pieces