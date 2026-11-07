extends RefCounted

# The suit is an upright box whose origin is the soles of its boots.
# Terrain queries include both soil and registered crystal cells.
const CELL_SIZE := 0.125
const HEIGHT := 1.25
const HALF_WIDTH := 0.18
const JUMP_SPEED := 5.2
const GRAVITY := 12.0
const MAX_STEP_HEIGHT := 0.25
const GROUND_PROBE := 0.012
const EPSILON := 0.00001
const MAX_DELTA := 0.25
const MAX_HORIZONTAL_SPEED := 32.0
const TERMINAL_SPEED := 24.0
const MAX_SUBSTEP_TIME := 1.0 / 60.0
const MAX_SUBSTEP_DISTANCE := CELL_SIZE * 0.5

var vertical_speed := 0.0
var grounded := false
var _jump_was_held := false


func reset(jump_held: bool = false) -> void:
	vertical_speed = 0.0
	grounded = false
	_jump_was_held = jump_held


func sync_jump_input(held: bool) -> void:
	# Menus use this without advancing gravity. Holding Space while closing a
	# menu must not create a new press, nor should it reset an existing jump.
	_jump_was_held = held


func has_clearance(terrain: Node, x: float, z: float, feet: float) -> bool:
	var at := Vector3(x, feet, z)
	if not is_instance_valid(terrain) or not at.is_finite():
		return false
	var first: Vector3i = terrain.world_to_cell(_body_min(at) + Vector3.ONE * EPSILON)
	var last: Vector3i = terrain.world_to_cell(_body_max(at) - Vector3.ONE * EPSILON)
	for iz in range(first.z, last.z + 1):
		for ix in range(first.x, last.x + 1):
			for iy in range(first.y, last.y + 1):
				if terrain.is_solid_cell(Vector3i(ix, iy, iz)):
					return false
	return true


func step(terrain: Node, at: Vector3, horizontal_velocity: Vector3, delta: float,
		jump_held: bool = false, position_constraint: Callable = Callable()) -> Vector3:
	var pressed := jump_held and not _jump_was_held
	_jump_was_held = jump_held
	if not at.is_finite():
		reset(jump_held)
		return Vector3.ZERO
	if not is_instance_valid(terrain) or not is_finite(delta) or delta <= 0.0:
		return at
	if not is_finite(vertical_speed):
		vertical_speed = 0.0
	var velocity := horizontal_velocity if horizontal_velocity.is_finite() else Vector3.ZERO
	velocity.y = 0.0
	velocity = velocity.limit_length(MAX_HORIZONTAL_SPEED)
	var elapsed := minf(delta, MAX_DELTA)
	var position := at
	grounded = false
	if vertical_speed <= 0.0:
		var down := _sweep_axis(terrain, position, 1, -GROUND_PROBE)
		if down > -GROUND_PROBE + EPSILON:
			position.y += down
			vertical_speed = 0.0
			grounded = true
	if pressed and grounded:
		vertical_speed = JUMP_SPEED
		grounded = false
	var steps := maxi(1, maxi(ceili(elapsed / MAX_SUBSTEP_TIME),
		ceili(velocity.length() * elapsed / MAX_SUBSTEP_DISTANCE)))
	var dt := elapsed / float(steps)
	for index in range(steps):
		var before_horizontal := position
		var target := _constrain(position + velocity * dt, position_constraint)
		position = _move_horizontal_axis(terrain, position, 0, target.x - position.x, grounded)
		position = _move_horizontal_axis(terrain, position, 2, target.z - position.z, grounded)
		# Axis sliding can briefly take a corner outside a circular boundary.
		# Sweep the correction too; if obstructed, retain the safe starting point.
		var constrained := _constrain(position, position_constraint)
		if Vector2(position.x - constrained.x, position.z - constrained.z).length_squared() > EPSILON * EPSILON:
			var corrected := position
			corrected.x += _sweep_axis(terrain, corrected, 0, constrained.x - corrected.x)
			corrected.z += _sweep_axis(terrain, corrected, 2, constrained.z - corrected.z)
			if Vector2(corrected.x - constrained.x, corrected.z - constrained.z).length_squared() <= EPSILON * EPSILON:
				position = corrected
			else:
				position = before_horizontal
		var next_speed := maxf(-TERMINAL_SPEED, vertical_speed - GRAVITY * dt)
		var vertical_distance := (vertical_speed + next_speed) * 0.5 * dt
		var moved := _sweep_axis(terrain, position, 1, vertical_distance)
		position.y += moved
		if absf(moved - vertical_distance) > EPSILON:
			grounded = vertical_distance < 0.0
			vertical_speed = 0.0
		else:
			grounded = false
			vertical_speed = next_speed
	# Finish tiny downward gaps at exact voxel faces, without snapping up onto
	# any surface above the feet (especially the top of an overhang).
	if vertical_speed <= 0.0:
		var down := _sweep_axis(terrain, position, 1, -GROUND_PROBE)
		if down > -GROUND_PROBE + EPSILON:
			position.y += down
			vertical_speed = 0.0
			grounded = true
	return position


func _constrain(at: Vector3, constraint: Callable) -> Vector3:
	if not constraint.is_valid():
		return at
	var result: Variant = constraint.call(at)
	if result is Vector3 and result.is_finite():
		# Only horizontal limits belong to the caller; vertical collision stays
		# under the grid solver's control.
		return Vector3(result.x, at.y, result.z)
	return at


func _move_horizontal_axis(terrain: Node, at: Vector3, axis: int, distance: float, may_step: bool) -> Vector3:
	if absf(distance) <= EPSILON:
		return at
	var allowed := _sweep_axis(terrain, at, axis, distance)
	# The first slide axis may have just walked off a ledge. Recheck support
	# before the second axis attempts a stair, instead of using stale grounded.
	if may_step and absf(allowed - distance) > EPSILON and _sweep_axis(terrain, at, 1, -GROUND_PROBE) > -GROUND_PROBE + EPSILON:
		var raised := _try_step_up(terrain, at, axis, distance)
		if absf(raised[axis] - at[axis] - distance) <= EPSILON:
			return raised
	var result := at
	result[axis] += allowed
	return result


func _try_step_up(terrain: Node, at: Vector3, axis: int, distance: float) -> Vector3:
	for count in range(1, roundi(MAX_STEP_HEIGHT / CELL_SIZE) + 1):
		var rise := float(count) * CELL_SIZE
		if _sweep_axis(terrain, at, 1, rise) < rise - EPSILON:
			continue
		var raised := at + Vector3.UP * rise
		var horizontal := _sweep_axis(terrain, raised, axis, distance)
		if absf(horizontal - distance) > EPSILON:
			continue
		raised[axis] += horizontal
		var down := _sweep_axis(terrain, raised, 1, -rise - GROUND_PROBE)
		if down <= -rise - GROUND_PROBE + EPSILON:
			continue
		raised.y += down
		if raised.y >= at.y - EPSILON and raised.y <= at.y + MAX_STEP_HEIGHT + EPSILON:
			return raised
	return at


func _body_min(at: Vector3) -> Vector3:
	return at + Vector3(-HALF_WIDTH, 0.0, -HALF_WIDTH)


func _body_max(at: Vector3) -> Vector3:
	return at + Vector3(HALF_WIDTH, HEIGHT, HALF_WIDTH)


func _sweep_axis(terrain: Node, at: Vector3, axis: int, distance: float) -> float:
	if absf(distance) <= EPSILON:
		return distance
	var direction := 1 if distance > 0.0 else -1
	var lower := _body_min(at)
	var upper := _body_max(at)
	var front := upper[axis] if direction > 0 else lower[axis]
	var first: Vector3i = terrain.world_to_cell(lower + Vector3.ONE * EPSILON)
	var last: Vector3i = terrain.world_to_cell(upper - Vector3.ONE * EPSILON)
	var front_point := at
	front_point[axis] = front + float(direction) * EPSILON
	var start_cell: Vector3i = terrain.world_to_cell(front_point)
	front_point[axis] = front + distance - float(direction) * EPSILON
	var end_cell: Vector3i = terrain.world_to_cell(front_point)
	var across_a := (axis + 1) % 3
	var across_b := (axis + 2) % 3
	for plane in range(start_cell[axis], end_cell[axis] + direction, direction):
		var cell := Vector3i.ZERO
		cell[axis] = plane
		for a in range(first[across_a], last[across_a] + 1):
			cell[across_a] = a
			for b in range(first[across_b], last[across_b] + 1):
				cell[across_b] = b
				if terrain.is_solid_cell(cell):
					var center: Vector3 = terrain.cell_center(cell)
					var stop := center[axis] - float(direction) * CELL_SIZE * 0.5 - front
					return clampf(stop, 0.0, distance) if direction > 0 else clampf(stop, distance, 0.0)
	return distance
