extends Node
## Manual Steam check on ONE PC (not part of tools\test.cmd, because it needs Steam running
## and signed in). It opens a Steam game as host, searches Steam for our games, and checks
## its own game shows up. That proves the add-on loads, Steam starts, lobbies are created
## with our tag and version, and searching works.
##
## It cannot test a real connection: that needs a second Steam account on another PC.
##   godot --headless --path <project> res://tests/steam_check.tscn

const TIMEOUT := 40.0
const SEARCH_ATTEMPTS := 5
const SEARCH_DELAY := 3.0

var _session: NetworkSession


func _ready() -> void:
	_session = NetworkSession.new()
	add_child(_session)
	get_tree().create_timer(TIMEOUT).timeout.connect(func() -> void: _finish("timed out"))
	var problem := _session.host_steam()
	if problem != "":
		_finish(problem)
		return
	var hosted := [false]
	_session.steam_hosted.connect(func() -> void: hosted[0] = true)
	_session.failed.connect(func(reason: String) -> void: _finish(reason))
	while not hosted[0]:
		await get_tree().process_frame
	print("  ok    hosting a Steam lobby as peer ", multiplayer.get_unique_id())

	var found: Array = []
	var searched := [false]
	_session.steam_games_found.connect(func(games: Array) -> void:
		found.assign(games)
		searched[0] = true
	)
	var own := false
	# A new lobby can take a few seconds to appear in Steam's search.
	for attempt in SEARCH_ATTEMPTS:
		await get_tree().create_timer(SEARCH_DELAY).timeout
		searched[0] = false
		_session.find_steam_games()
		while not searched[0]:
			await get_tree().process_frame
		print("  ..    search %d returned %d game(s): %s" % [attempt + 1, found.size(), found])
		for game: Dictionary in found:
			own = own or game.id == _session._lobby_id
		if own:
			break
	if not own:
		_finish("our own lobby %d was not in the search results" % _session._lobby_id)
		return
	print("  ok    our own game was found by searching")
	_finish("")


func _finish(problem: String) -> void:
	print("STEAM CHECK PASS" if problem == "" else "STEAM CHECK FAIL: " + problem)
	_session.leave()
	get_tree().quit(0 if problem == "" else 1)
