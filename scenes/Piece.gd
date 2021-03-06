"""
Contains logic for moving/rotating pieces, handling player input, locking pieces into the playfield.
"""
extends Control

# All gravity constants are integers like '16', which actually correspond to fractions like '16/256' which means the
# piece takes 16 frames to drop one row. GRAVITY_DENOMINATOR is the denominator of that fraction.
const GRAVITY_DENOMINATOR = 256

# The maximum number of 'lock resets' the player is allotted for a single piece. A lock reset occurs when a piece is at
# the bottom of the screen but the player moves or rotates it to prevent from locking.
const MAX_LOCK_RESETS = 12

# The gravity constant used when the player soft-drops a piece. This drop speed should be slow enough that the player
# can slide pieces into nooks left in vertical stacks.
const DROP_G = 128

"""
Contains the settings and state for the currently active piece.
"""
class Piece:
	var pos = Vector2(3, 3)
	var rotation = 0
	
	# Amount of accumulated gravity for this piece. When this number reaches 256, the piece will move down one row
	var gravity = 0
	
	# Number of frames this piece has been locked into the playfield, or '0' if the piece is not locked
	var lock = 0
	
	# Number of 'lock resets' which have been applied to this piece
	var lock_resets = 0
	
	# Number of 'floor kicks' which have been applied to this piece
	var floor_kicks = 0
	
	# Number of frames to wait before spawning the piece after this one
	var spawn_delay = 0
	
	# Piece shape, color, kick information
	var type
	
	func setType(new_type):
		type = new_type
		rotation %= type.pos_arr.size()
	
	func _init(piece_type):
		setType(piece_type)
	
	"""
	Returns the rotational state the piece will be in if it rotates clockwise.
	"""
	func cw_rotation(in_rotation = -1):
		if in_rotation == -1:
			in_rotation = rotation
		return (in_rotation + 1) % type.pos_arr.size()
	
	"""
	Returns the rotational state the piece will be in if it rotates 180 degrees.
	"""
	func flip_rotation(in_rotation = -1):
		if in_rotation == -1:
			in_rotation = rotation
		return (in_rotation + 2) % type.pos_arr.size()

	"""
	Returns the rotational state the piece will be in if it rotates counter-clockwise.
	"""
	func ccw_rotation(in_rotation = -1):
		if in_rotation == -1:
			in_rotation = rotation
		return (in_rotation + 3) % type.pos_arr.size()

# signal emitted when the current piece can't be placed in the playfield
signal game_over

# information about the current 'speed level', such as how fast pieces drop, how long it takes them to lock into the
# playfield, and how long to pause when clearing lines.
var piece_speed

# settings and state for the currently active piece.
var piece

var target_piece_pos
var target_piece_rotation
var tile_map_dirty = false

var input_left_frames = 0
var input_right_frames = 0
var input_down_frames = 0
var input_hard_drop_frames = 0
var input_cw_frames = 0
var input_ccw_frames = 0
var dead = false

onready var Playfield = get_node("../Playfield")
onready var NextPieces = get_node("../NextPieces")
onready var PieceTypes = preload("res://scenes/PieceTypes.gd").new()
onready var PieceSpeeds = preload("res://scenes/PieceSpeeds.gd").new()

func _ready():
	# ensure the piece isn't visible outside the playfield
	set_clip_contents(true)
	
	piece = Piece.new(PieceTypes.piece_null)
	piece_speed = PieceSpeeds.all_speeds[0]
	update_tile_map()

func clear_piece():
	dead = true
	piece = Piece.new(PieceTypes.piece_null)
	tile_map_dirty = true

func start_game():
	dead = false
	piece = Piece.new(PieceTypes.piece_null)
	tile_map_dirty = true
	Playfield.clock_running = true

func set_piece_speed(new_piece_speed):
	piece_speed = PieceSpeeds.all_speeds[clamp(new_piece_speed, 0, PieceSpeeds.all_speeds.size() - 1)]

func new_piece():
	var piece_type
	if NextPieces == null:
		piece_type = PieceTypes.all_types[randi() % PieceTypes.all_types.size()]
	else:
		piece_type = NextPieces.pop_piece_type()
	piece = Piece.new(piece_type)
	tile_map_dirty = true
	
	# apply initial rotation
	if input_cw_frames > 1 && input_ccw_frames > 1:
		piece.rotation = piece.flip_rotation(piece.rotation)
		$RotateSound.play()
	elif input_cw_frames > 1:
		piece.rotation = piece.cw_rotation(piece.rotation)
		$RotateSound.play()
	elif input_ccw_frames > 1:
		piece.rotation = piece.ccw_rotation(piece.rotation)
		$RotateSound.play()
	
	# apply initial infinite DAS
	var initial_das_dir = 0
	if input_left_frames >= piece_speed.delayed_auto_shift_delay:
		initial_das_dir -= 1
	if input_right_frames >= piece_speed.delayed_auto_shift_delay:
		initial_das_dir += 1
	
	if initial_das_dir == -1:
		# player is holding left; start piece on the left side
		var old_pos = piece.pos
		reset_piece_target()
		kick_piece([Vector2(-4, 0), Vector2(-4, -1), Vector2(-3, 0), Vector2(-3, -1), Vector2(-2, 0), Vector2(-2, -1), Vector2(-1, 0), Vector2(-1, -1)])
		move_piece_to_target()
		if old_pos != piece.pos:
			$MoveSound.play()
	elif initial_das_dir == 0:
		reset_piece_target()
		kick_piece([Vector2(0, 0), Vector2(0, -1), Vector2(-1, 0), Vector2(-1, -1), Vector2(1, 0), Vector2(1, -1)])
		move_piece_to_target()
	elif initial_das_dir == 1:
		# player is holding right; start piece on the right side
		var old_pos = piece.pos
		reset_piece_target()
		kick_piece([Vector2(4, 0), Vector2(4, -1), Vector2(3, 0), Vector2(3, -1), Vector2(2, 0), Vector2(2, -1), Vector2(1, 0), Vector2(1, -1)])
		move_piece_to_target()
		if old_pos != piece.pos:
			$MoveSound.play()
	
	# lose?
	if !can_move_piece_to(piece.pos, piece.rotation):
		Playfield.write_piece(piece.pos, piece.rotation, piece.type, piece_speed.line_clear_delay, true)
		$GameOverSound.play()
		Playfield.clock_running = false
		dead = true
		emit_signal("game_over")

func _physics_process(delta):
	input_left_frames = increment_input_frames(input_left_frames, "ui_left")
	input_right_frames = increment_input_frames(input_right_frames, "ui_right")
	input_down_frames = increment_input_frames(input_down_frames, "ui_down")
	input_hard_drop_frames = increment_input_frames(input_hard_drop_frames, "hard_drop")
	input_cw_frames = increment_input_frames(input_cw_frames, "rotate_cw")
	input_ccw_frames = increment_input_frames(input_ccw_frames, "rotate_ccw")
	
	if dead:
		return
	
	# Pressing a new key overrides das. Otherwise pieces can feel like they get stuck to a wall, if you press left
	# after holding right
	if Input.is_action_just_pressed("ui_left"):
		input_right_frames = 0
	if Input.is_action_just_pressed("ui_right"):
		input_left_frames = 0
	
	if PieceTypes.is_null(piece.type):
		# no piece; spawn a piece?
		if Playfield != null && !Playfield.ready_for_new_piece():
			pass
		elif piece.spawn_delay <= 0:
			new_piece()
		else:
			piece.spawn_delay -= 1
		return;
	
	if Input.is_action_pressed("hard_drop") \
			or Input.is_action_pressed("ui_down") \
			or Input.is_action_pressed("ui_left") \
			or Input.is_action_pressed("ui_right") \
			or Input.is_action_pressed("rotate_cw") \
			or Input.is_action_pressed("rotate_ccw"):
		apply_player_input()
	
	apply_gravity()
	apply_lock()
	
	if piece.lock > piece_speed.lock_delay:
		$LockSound.play()
		if Playfield != null:
			if Playfield.write_piece(piece.pos, piece.rotation, piece.type, piece_speed.line_clear_delay):
				# line was cleared; reduced appearance delay
				piece.spawn_delay = piece_speed.line_appearance_delay
			else:
				piece.spawn_delay = piece_speed.appearance_delay
		piece.setType(PieceTypes.piece_null)
		tile_map_dirty = true
	
	if tile_map_dirty:
		update_tile_map()
		tile_map_dirty = false

func increment_input_frames(frames, action):
	if Input.is_action_pressed(action):
		return frames + 1
	return 0

func apply_player_input():
	if piece.lock > piece_speed.lock_delay:
		# piece is locked; ignore all input
		return
	
	var old_piece_pos = piece.pos
	var old_piece_rotation = piece.rotation
	
	reset_piece_target()
	
	calc_target_rotation()
	if target_piece_rotation != piece.rotation && !can_move_piece_to(target_piece_pos, target_piece_rotation):
		kick_piece()
	move_piece_to_target(true)
	
	calc_target_position()
	if !move_piece_to_target(true):
		# automatically trigger DAS if you push against a piece. otherwise, pieces might slip past a nook if you're
		# holding a direction before DAS triggers
		if Input.is_action_just_pressed("ui_left"):
			input_left_frames = 3600
		if Input.is_action_just_pressed("ui_right"):
			input_right_frames = 3600
	
	if Input.is_action_just_pressed("hard_drop") or input_hard_drop_frames > piece_speed.delayed_auto_shift_delay:
		while(move_piece_to_target()):
			target_piece_pos.y += 1
		# lock piece
		piece.lock = piece_speed.lock_delay
		piece.lock_resets = MAX_LOCK_RESETS
		$DropSound.play()
	
	if old_piece_pos != piece.pos || old_piece_rotation != piece.rotation:
		if piece.lock > 0 && piece.lock_resets < MAX_LOCK_RESETS:
			# lock reset
			piece.lock = 0
			piece.lock_resets += 1
			if piece.lock_resets >= MAX_LOCK_RESETS:
				# last reset has been performed: lock piece
				piece.lock = piece_speed.lock_delay
	
	# if the player moved the piece down, don't apply gravity
	if old_piece_pos.y < piece.pos.y:
		piece.gravity = max(piece.gravity - GRAVITY_DENOMINATOR, 0)	

"""
Kicks a rotated piece into a nearby empty space. This should only be called when rotation has already failed.
"""
func kick_piece(kicks = null):
	if kicks == null:
		print(piece.type.string," to ",piece.rotation," -> ",target_piece_rotation)
		if target_piece_rotation == piece.cw_rotation():
			kicks = piece.type.cw_kicks[piece.rotation]
		elif target_piece_rotation == piece.ccw_rotation():
			kicks = piece.type.ccw_kicks[target_piece_rotation]
		else:
			kicks = []
	else:
		print(piece.type.string," to: ",kicks)

	for kick in kicks:
		if kick.y < 0 && piece.floor_kicks >= piece.type.max_floor_kicks:
			print("no: ", kick, " (too many floor kicks)")
			continue
		if can_move_piece_to(target_piece_pos + kick, target_piece_rotation):
			target_piece_pos += kick
			if kick.y < 0:
				piece.floor_kicks += 1
			print("yes: ", kick)
			break
		else:
			print("no: ", kick)
	print("-")

func apply_gravity():
	if Input.is_action_pressed("ui_down"):
		# soft drop
		piece.gravity += max(DROP_G, piece_speed.gravity)
	else:
		piece.gravity += piece_speed.gravity;
	while (piece.gravity >= GRAVITY_DENOMINATOR):
		piece.gravity -= GRAVITY_DENOMINATOR
		reset_piece_target()
		target_piece_pos.y = piece.pos.y + 1
		move_piece_to_target()

func apply_lock():
	if !can_move_piece_to(Vector2(piece.pos.x, piece.pos.y + 1), piece.rotation):
		piece.lock += 1
	else:
		piece.lock = 0

func can_move_piece_to(pos, rotation):
	var valid_target_pos = true
	for block_pos in piece.type.pos_arr[rotation]:
		var target_block_pos = Vector2(pos.x + block_pos.x, pos.y + block_pos.y)
		valid_target_pos = valid_target_pos && target_block_pos.x >= 0 and target_block_pos.x < Playfield.COL_COUNT
		valid_target_pos = valid_target_pos && target_block_pos.y >= 0 and target_block_pos.y < Playfield.ROW_COUNT
		if Playfield != null:
			valid_target_pos = valid_target_pos && Playfield.is_cell_empty(target_block_pos.x, target_block_pos.y)
	return valid_target_pos

func move_piece_to_target(play_sfx = false):
	var valid_target_pos = can_move_piece_to(target_piece_pos, target_piece_rotation)
	
	if valid_target_pos:
		if play_sfx:
			if piece.rotation != target_piece_rotation:
				$RotateSound.play()
			if piece.pos != target_piece_pos:
				$MoveSound.play()
		piece.pos = target_piece_pos
		piece.rotation = target_piece_rotation
		tile_map_dirty = true
	
	reset_piece_target()
	return valid_target_pos

func reset_piece_target():
	target_piece_pos = piece.pos
	target_piece_rotation = piece.rotation

func calc_target_position():
	if Input.is_action_just_pressed("ui_left") or input_left_frames >= piece_speed.delayed_auto_shift_delay:
		target_piece_pos.x -= 1
	
	if Input.is_action_just_pressed("ui_right") or input_right_frames >= piece_speed.delayed_auto_shift_delay:
		target_piece_pos.x += 1

func calc_target_rotation():
	if Input.is_action_just_pressed("rotate_cw"):
		target_piece_rotation = piece.cw_rotation(target_piece_rotation)
		
	if Input.is_action_just_pressed("rotate_ccw"):
		target_piece_rotation = piece.ccw_rotation(target_piece_rotation)

func update_tile_map():
	$TileMap.clear()
	for i in range(0, piece.type.pos_arr[piece.rotation].size()):
		var block_pos = piece.type.pos_arr[piece.rotation][i]
		var block_color = piece.type.color_arr[piece.rotation][i]
		$TileMap.set_cell(piece.pos.x + block_pos.x, piece.pos.y + block_pos.y, \
				0, false, false, false, block_color)
