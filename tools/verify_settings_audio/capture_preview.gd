extends SceneTree

## Renders settings_preview.tscn in windowed mode and saves crisp PNG screenshots
## of the SettingsOverlay (Graphics tab + Audio & Voice tab) for visual verification.

const SETTINGS_PREVIEW_PATH := "res://scenes/ui/settings/settings_preview.tscn"
const OUT_GRAPHICS := "res://tools/verify_settings_audio/settings_preview_graphics.png"
const OUT_AUDIO := "res://tools/verify_settings_audio/settings_preview_audio.png"
const OUT_READING := "res://tools/verify_settings_audio/settings_preview_reading.png"


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	var preview_scene := load(SETTINGS_PREVIEW_PATH) as PackedScene
	if preview_scene == null:
		push_error("Failed to load " + SETTINGS_PREVIEW_PATH)
		quit(1)
		return
	var preview := preview_scene.instantiate()
	root.add_child(preview)
	var smgr: Node = preview.get("settings_manager")
	var overlay: CanvasLayer = preview.get("settings_overlay")
	smgr.set("mobile_override", 0)
	smgr.call("reset_to_defaults", false)
	overlay.call("refresh_from_settings")

	# Wait for open spring animation to settle
	await _wait_frames(32)
	await _save_shot(OUT_GRAPHICS)

	overlay.call("select_tab", "audio", false)
	overlay.call("play_test_chime")
	await _wait_frames(12)
	await _save_shot(OUT_AUDIO)

	overlay.call("select_tab", "reading", false)
	await _wait_frames(12)
	await _save_shot(OUT_READING)

	preview.queue_free()
	await create_timer(0.15).timeout
	print("PREVIEW CAPTURE COMPLETE")
	quit(0)


func _wait_frames(count: int) -> void:
	for _i: int in range(count):
		await process_frame


func _save_shot(res_path: String) -> void:
	var img := root.get_texture().get_image()
	if img == null:
		push_error("Failed to grab viewport image for " + res_path)
		return
	var abs_path := ProjectSettings.globalize_path(res_path)
	var err := img.save_png(abs_path)
	if err != OK:
		push_error("Failed to save PNG (%d): %s" % [err, abs_path])
	else:
		print("Saved screenshot: %s (%dx%d)" % [res_path, img.get_width(), img.get_height()])
