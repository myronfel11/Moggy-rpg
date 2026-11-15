class_name BossArena
extends Level
## The arena for "The Three Pillars": the Warden in the centre, three pillars on an outer
## ring, and a sentinel opposite each pillar, so every tracking ball has to be led across
## the room past the boss. The fight itself is run by the Encounter node (BossEncounter).

@onready var encounter: BossEncounter = $Encounter


func _setup_level() -> void:
	encounter.setup(self)
	var bar := BossBar.new()
	_hud.add_child(bar)
	bar.bind(self, encounter)


func _start_level() -> void:
	if encounter.auto_start:
		encounter.start()
