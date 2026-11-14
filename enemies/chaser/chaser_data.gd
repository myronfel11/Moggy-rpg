class_name ChaserData
extends EnemyData
## Stats for enemies that run at the player and lunge. Used with chaser.tscn.

@export_group("Lunge attack")
## Hit points removed from the player per lunge.
@export var damage := 10.0
## The enemy starts winding up once the player is within this many pixels.
@export var attack_range := 40.0
## Warning time before the lunge, in seconds. Longer is easier to dodge.
@export var windup := 0.45
## On: once the windup starts, hits no longer cancel it, so the player has to dodge or
## kill it in time. Off: any hit cancels the attack, which lets the player stun-lock it.
## Either way, hitting it during the lunge itself knocks it out of the attack.
@export var committed_windup := true
## Lunge speed in pixels per second. Distance covered is lunge_speed x lunge_duration.
@export var lunge_speed := 260.0
## How long the lunge lasts, in seconds.
@export var lunge_duration := 0.22
## Pause after a lunge before chasing again. This is the player's opening to counter.
@export var recovery := 0.6
## How hard the player is pushed when hit, in pixels per second.
@export var attack_knockback := 170.0
## Seconds both sides freeze when the lunge connects.
@export var attack_hit_stop := 0.06
