extends SceneTree

const GameAudio = preload("res://game_audio.gd")
var failed := false

func _initialize() -> void:
	call_deferred("run")

func require(condition: bool, description: String) -> void:
	if not condition:
		failed = true
		push_error("AUDIO FAIL: " + description)
		quit(1)
		assert(condition, description)

func active_voices(sfx: GameAudio) -> int:
	var count := 0
	for voice in sfx._voices:
		if voice.playing:
			count += 1
	return count

func check_pcm(stream: AudioStreamWAV, label: String) -> void:
	require(stream != null, label + " is loadable")
	require(stream.mix_rate == 32000 and not stream.stereo, label + " uses the documented sample format")
	require(stream.get_length() > 0.05 and stream.data.size() > 1000, label + " contains playable imported audio")
	# Source fidelity is checked separately from Godot's QOA-compressed imports.
	var source := AudioStreamWAV.load_from_file(stream.resource_path, {"compress/mode": 0})
	require(source.format == AudioStreamWAV.FORMAT_16_BITS, label + " has 16-bit PCM source data")
	var peak := 0
	for offset in range(0, source.data.size(), 2):
		peak = maxi(peak, absi(source.data.decode_s16(offset)))
	require(peak > 500 and peak < 23000, label + " is audible PCM with source headroom")

func run() -> void:
	var sfx := GameAudio.new()
	root.add_child(sfx)
	require(sfx.process_mode == Node.PROCESS_MODE_ALWAYS, "audio controller can stop loops while the world is paused")
	require(sfx._voices.size() == GameAudio.MAX_VOICES, "one-shot voice pool is bounded")
	var file_count := 0
	for event: StringName in GameAudio.EVENTS:
		var streams: Array = sfx._bank[event]
		require(streams.size() == GameAudio.EVENTS[event].files.size(), "every event variant loads: " + str(event))
		for stream: AudioStreamWAV in streams:
			check_pcm(stream, str(event))
			file_count += 1
	var loop := sfx._drill_player.stream as AudioStreamWAV
	check_pcm(loop, "drill loop")
	require(loop.loop_mode == AudioStreamWAV.LOOP_FORWARD, "drill stream loops")
	require(loop.loop_begin == 0 and loop.loop_end == roundi(1.6 * loop.mix_rate), "loop bounds use frames even with compressed resource data")
	require(loop.loop_end > loop.loop_begin and loop.get_length() > 1.0, "loop has a nonempty cycle")
	var loop_source := AudioStreamWAV.load_from_file(loop.resource_path, {"compress/mode": 0})
	require(loop_source.data.decode_s16(0) == 0 and loop_source.data.decode_s16(loop_source.data.size() - 2) == 0, "loop seam has no amplitude discontinuity")
	var bus := AudioServer.get_bus_index(GameAudio.BUS_NAME)
	require(bus >= 0 and AudioServer.get_bus_effect_count(bus) > 0, "SFX bus has a peak limiter")

	sfx.set_drilling(true, 2.0)
	sfx._process(0.08)
	require(sfx._drill_player.playing and sfx._drilling, "drilling starts dedicated looping playback")
	require(sfx._drill_player.pitch_scale > 1.0 and sfx._drill_player.volume_db < -15.0, "faster drill remains at a modest gain")
	sfx.set_drilling(false)
	sfx._process(0.10)
	require(not sfx._drill_player.playing, "releasing drill fades and stops the loop")
	sfx.set_walking(true)
	sfx._process(0.06)
	require(int(sfx._variants.get(&"footstep", 0)) == 1, "walking schedules grounded gravel footsteps")
	sfx.stop_gameplay_loops()
	require(not sfx._walking and not sfx._drilling and not sfx._drill_player.playing, "modal stop clears walking and drilling")

	sfx.play_event(&"oxygen_pickup")
	var pickups := int(sfx._variants.get(&"oxygen_pickup", 0))
	for index in range(200):
		sfx.play_event(&"oxygen_pickup")
	require(int(sfx._variants.get(&"oxygen_pickup", 0)) == pickups, "hundreds of simultaneous grains coalesce into one pickup cue")
	sfx.play_event(&"oxygen_critical")
	var alarms := int(sfx._variants.get(&"oxygen_critical", 0))
	for index in range(100):
		sfx.play_event(&"oxygen_critical")
	require(int(sfx._variants.get(&"oxygen_critical", 0)) == alarms, "critical alarm does not repeat every frame")
	for index in range(100):
		sfx._next_allowed.erase(&"dig")
		sfx.play_event(&"dig")
	require(sfx._voices.size() == GameAudio.MAX_VOICES and active_voices(sfx) <= GameAudio.MAX_VOICES, "rapid gameplay cannot create unbounded voices")
	sfx.play_event(&"unknown_event")

	var ui := Control.new()
	root.add_child(ui)
	var button := Button.new()
	ui.add_child(button)
	sfx.bind_ui(ui)
	sfx.bind_ui(ui)
	sfx._next_allowed.erase(&"ui_click")
	var clicks := int(sfx._variants.get(&"ui_click", 0))
	button.pressed.emit()
	require(int(sfx._variants.get(&"ui_click", 0)) == clicks + 1, "button binding is idempotent")
	var dynamic := Button.new()
	ui.add_child(dynamic)
	sfx._next_allowed.erase(&"ui_click")
	dynamic.pressed.emit()
	require(int(sfx._variants.get(&"ui_click", 0)) == clicks + 2, "new UI buttons also receive feedback")

	sfx.set_drilling(true)
	sfx.set_walking(true)
	paused = true
	await process_frame
	await process_frame
	require(not sfx._drill_player.playing and not sfx._walking, "pause stops gameplay loops")
	sfx._next_allowed.erase(&"ui_click")
	sfx.play_event(&"ui_click")
	require(int(sfx._variants.get(&"ui_click", 0)) == clicks + 3, "paused menus still provide button feedback")
	paused = false
	sfx.set_drilling(true)
	sfx._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	require(not sfx._drill_player.playing and active_voices(sfx) == 0, "focus loss stops all sound")
	sfx._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	require(not sfx._drill_player.playing, "focus return does not resume an abandoned drill")
	sfx.set_drilling(true)
	sfx.set_muted(true)
	require(sfx.muted and not sfx._drill_player.playing and active_voices(sfx) == 0, "mute stops active loops and one-shots")
	sfx._next_allowed.clear()
	sfx.play_event(&"crystal_pickup")
	sfx.set_drilling(true)
	require(active_voices(sfx) == 0 and not sfx._drill_player.playing, "mute also blocks future playback")
	sfx.set_muted(false)
	sfx.play_event(&"crystal_pickup")
	require(active_voices(sfx) == 1, "unmute restores explicit new playback")
	sfx.set_muted(true)
	sfx.queue_free()
	ui.queue_free()
	await create_timer(0.20, true).timeout
	print("AUDIO_OK files=%d events=%d pcm_headroom=true loop_bounds=true bounded_voices=true pickup_coalescing=true paused=true focused=true muted=true dynamic_ui=true" % [file_count + 1, GameAudio.EVENTS.size()])
	quit(1 if failed else 0)
