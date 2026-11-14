class_name GameCamera
extends Camera2D
## Follows a target and shakes on impact.
##
## Shake uses "trauma": hits add trauma, trauma drains over time, and the shake strength
## is trauma squared. Squaring keeps small hits subtle and makes big hits punch.
## Anything can shake the screen without holding a reference to the camera:
##     get_tree().call_group(&"game_camera", &"add_trauma", 0.4)

## The node to follow.
@export var target: Node2D
## How quickly the camera catches up. Higher is snappier.
@export var follow_speed := 12.0
## Shake distance in pixels at full trauma.
@export var max_shake := 8.0
## Trauma lost per second.
@export var trauma_decay := 2.2

var _trauma := 0.0


func _ready() -> void:
	add_to_group(&"game_camera")
	# Move in step with physics so the camera and the characters never drift apart.
	process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS


## Jumps straight to the target with no easing (use after spawning or teleporting).
func snap_to_target() -> void:
	if is_instance_valid(target):
		global_position = target.global_position


## Adds shake. 0.3 is a light hit, 0.6 is a heavy one, 1.0 is the maximum.
func add_trauma(amount: float) -> void:
	_trauma = minf(1.0, _trauma + amount)


func _physics_process(delta: float) -> void:
	if is_instance_valid(target):
		# Frame-rate independent easing toward the target.
		var weight := 1.0 - exp(-follow_speed * delta)
		global_position = global_position.lerp(target.global_position, weight)
	_trauma = maxf(0.0, _trauma - trauma_decay * delta)
	var strength := _trauma * _trauma * max_shake
	offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * strength
