class_name ThreePillarsData
extends Resource
## Every tunable number for "The Three Pillars" boss encounter, in one file.
## Open bosses/three_pillars/data/three_pillars.tres in the editor to tune the fight.

@export var boss_name := "THE WARDEN"

@export_group("Boss")
## Boss health with one player.
@export var boss_health := 1200.0
## Extra boss health for each additional player present when the fight starts (0.6 = +60%).
@export var health_per_extra_player := 0.6
## The first damage phase stops at this share of health (0.5 = 50%).
@export_range(0.05, 0.95) var health_gate := 0.5

@export_group("Sniper laser")
## Seconds the reticle sits on the chosen player before charging starts.
@export var acquire_time := 0.6
## Seconds the laser charges while following its target. Longer is easier to dodge.
@export var charge_time := 1.6
## Seconds the direction is frozen before it fires: the last chance to step out.
@export var lock_time := 0.5
## Seconds the beam is visible.
@export var fire_time := 0.15
## Seconds after firing before the boss picks its next target.
@export var recover_time := 1.2
## Extra seconds of calm between attacks.
@export var idle_time := 2.0
## Half the beam's width in pixels. A player whose centre is closer than this plus their
## own radius is hit.
@export var beam_half_width := 6.0

@export_group("Sentinels (mini-bosses)")
@export var sentinel_health := 150.0
## Seconds between tracking balls from each sentinel.
@export var fire_interval := 4.5
## Most tracking balls one sentinel can have out at once.
@export var max_balls_each := 2
## Matching tracking balls a pillar must take before it falls and its sentinel's shield
## breaks. Wrong-colour balls never count.
@export_range(1, 10) var pillar_hits := 3

@export_group("Tracking balls")
## Ball speed in pixels per second (players run at 120).
@export var ball_speed := 95.0
## How quickly a ball can turn, in radians per second. Low values are easy to lead.
@export var ball_turn_rate := 1.6
## Seconds before a ball fizzles on its own.
@export var ball_lifetime := 10.0
## Damage to a player the ball touches.
@export var ball_damage := 15.0

@export_group("Bombs")
## Seconds E must be held to pick up a bomb.
@export var pickup_hold := 1.0
## Seconds E must be held to slam a bomb into the boss.
@export var slam_hold := 1.5
## How close to the boss's centre a carrier must be to slam, in pixels.
@export var slam_range := 60.0
## Movement speed while carrying a bomb (0.85 = 15% slower).
@export var carry_speed := 0.85

@export_group("Flow")
## Seconds before the fight starts after arriving.
@export var intro_time := 2.0
## Seconds of the 50% health gate transition before the mechanics restart.
@export var gate_time := 2.5
## Revives the whole team shares for one attempt.
@export var revive_pool := 3
## Seconds a downed player waits before a revive brings them back.
@export var revive_delay := 5.0

@export_group("Look")
## Colour of each pillar, its sentinel and its balls: index 0, 1, 2.
@export var slot_colors: Array[Color] = [Color(0.3, 0.95, 1.0), Color(1.0, 0.7, 0.2), Color(1.0, 0.35, 0.85)]
