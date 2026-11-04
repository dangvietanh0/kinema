extends Control
## Graphics workstream suite: renderer risk state, effective profiles,
## capability unlock and the settings graphics risk controls.
##
## Everything here is pure state and UI-tree inspection. No test claims a GPU
## effect ran on a device; the persistence tests write the real preference path
## and restore it before the suite ends.

const GfxScript = preload("res://src/core/gfx.gd")
const SettingsPanelScript = preload("res://src/ui/settings_panel.gd")

var _failures: Array[String] = []
var _oks := 0
var _saved_prefs := ""
var _had_prefs := false


func _check(condition: bool, message: String) -> void:
	if condition:
		_oks += 1
		print("GRAPHICS OK: " + message)
	else:
		_failures.append(message)
		printerr("GRAPHICS FAIL: " + message)


func _ready() -> void:
	await get_tree().process_frame
	_had_prefs = FileAccess.file_exists(Gfx.PATH)
	if _had_prefs:
		_saved_prefs = FileAccess.get_file_as_string(Gfx.PATH)

	_test_defaults_and_persistence()
	_test_begin_risk_boot()
	_test_enable_and_disable()
	_test_risk_profile()
	_test_capabilities()

	_restore_preferences()
	var status := "PASS" if _failures.is_empty() else "FAIL"
	print("GRAPHICS %s (%d OK, %d FAIL)" % [status, _oks, _failures.size()])
	if not _failures.is_empty():
		for failure in _failures:
			printerr("  - " + failure)
	print("SUITE RESULT: %s" % status)
	get_tree().quit(0 if _failures.is_empty() else 1)


# -------------------------------------------------------------------------
# Helpers
# -------------------------------------------------------------------------

func _write_prefs(data: Dictionary) -> void:
	var file := FileAccess.open(Gfx.PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "  "))
	file.close()


func _restore_preferences() -> void:
	if _had_prefs:
		var file := FileAccess.open(Gfx.PATH, FileAccess.WRITE)
		file.store_string(_saved_prefs)
		file.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Gfx.PATH))
	_reset_risk()


func _reset_risk(enabled: bool = false, boot: String = "idle", last_error: String = "") -> void:
	Gfx.risk_enabled = enabled
	Gfx.risk_boot = boot
	Gfx.risk_last_error = last_error


func _fresh_gfx():
	var node = GfxScript.new()
	return node


# -------------------------------------------------------------------------
# Persisted state
# -------------------------------------------------------------------------

func _test_defaults_and_persistence() -> void:
	print("GRAPHICS STEP: risk state persistence")
	var fresh = _fresh_gfx()
	var data: Dictionary = fresh.to_dict()
	_check(bool(data.get("risk_enabled", true)) == false, "risk is disabled by default")
	_check(str(data.get("risk_boot", "")) == "idle", "risk boot is idle by default")
	_check(str(data.get("risk_last_error", "missing")) == "", "risk error is empty by default")
	fresh.free()

	_write_prefs({"preset": "balanced"})
	fresh = _fresh_gfx()
	fresh.load_preferences()
	_check(not bool(fresh.risk_enabled), "missing risk_enabled keeps the safe default")
	_check(str(fresh.risk_boot) == "idle", "missing risk_boot keeps the safe default")
	_check(str(fresh.risk_last_error) == "", "missing risk_last_error keeps the safe default")
	fresh.free()

	_write_prefs({"risk_enabled": true, "risk_boot": "sideways", "risk_last_error": "kept"})
	fresh = _fresh_gfx()
	fresh.load_preferences()
	_check(str(fresh.risk_boot) == "idle", "an unknown risk_boot normalizes to idle")
	_check(bool(fresh.risk_enabled), "a stored risk_enabled survives the reload")
	_check(str(fresh.risk_last_error) == "kept", "a stored risk_last_error survives the reload")
	fresh.free()

	_write_prefs({"risk_enabled": true, "risk_boot": "probing", "risk_last_error": ""})
	fresh = _fresh_gfx()
	fresh.load_preferences()
	_check(str(fresh.risk_boot) == "probing", "a probing boot survives a reload for startup")
	fresh.free()


# -------------------------------------------------------------------------
# Boot decision table
# -------------------------------------------------------------------------

func _test_begin_risk_boot() -> void:
	print("GRAPHICS STEP: risk boot decision table")
	_reset_risk(true, "idle", "")
	var decision: Dictionary = Gfx.begin_risk_boot("Android", "forward_plus")
	_check(str(decision.get("action", "")) == "probe", "an enabled Android Forward+ boot probes")
	_check(str(decision.get("boot", "")) == "probing", "a probe serializes probing before any profile applies")
	_check(str(decision.get("reason", "missing")) == "", "a fresh probe has no error reason")

	_reset_risk(true, "probing", "")
	decision = Gfx.begin_risk_boot("Android", "forward_plus")
	_check(str(decision.get("action", "")) == "revert", "a probing boot from the previous launch reverts")
	_check(str(decision.get("boot", "")) == "idle", "a revert returns the boot state to idle")
	_check(not bool(decision.get("risk_enabled", true)), "a revert disables the risk switch")
	_check(str(decision.get("reason", "")).contains("previous launch did not reach the editor"), "a revert explains the previous launch")

	_reset_risk(false, "probing", "")
	decision = Gfx.begin_risk_boot("Android", "forward_plus")
	_check(str(decision.get("action", "")) == "clear", "a probing boot with the switch off clears")
	_check(str(decision.get("boot", "")) == "idle", "a clear returns the boot state to idle")
	_check(str(decision.get("reason", "missing")) == "", "a clear has no scary reason")

	_reset_risk(true, "idle", "")
	decision = Gfx.begin_risk_boot("Android", "mobile")
	_check(str(decision.get("action", "")) == "none", "Mobile running never arms a probe")
	_check(str(decision.get("boot", "")) == "idle", "Mobile running keeps the boot state idle")
	_check(bool(decision.get("risk_enabled", false)), "Mobile running keeps the stored risk switch")

	_reset_risk(true, "idle", "")
	decision = Gfx.begin_risk_boot("Linux", "forward_plus")
	_check(str(decision.get("action", "")) == "none", "desktop never arms a risk probe")



# -------------------------------------------------------------------------
# Enable, disable and confirmation
# -------------------------------------------------------------------------

func _test_enable_and_disable() -> void:
	print("GRAPHICS STEP: risk enable and disable")
	_reset_risk(false, "idle", "")
	_check(Gfx.risk_supported("Android"), "risk is supported on Android")
	_check(Gfx.risk_supported("iOS"), "risk is supported on iOS")
	_check(not Gfx.risk_supported("Linux"), "risk is unsupported on Linux")

	_reset_risk(false, "idle", "")
	_check(not Gfx.risk_active("Android", "forward_plus"), "risk is inactive with the switch off")
	_reset_risk(true, "proven", "")
	_check(Gfx.risk_active("Android", "forward_plus"), "risk is active on Android Forward+")
	_check(not Gfx.risk_active("Android", "mobile"), "risk is inactive while Mobile runs")
	_check(not Gfx.risk_active("Linux", "forward_plus"), "risk is inactive on desktop")

	_write_prefs({"risk_enabled": false, "risk_boot": "idle", "risk_last_error": ""})
	_reset_risk(false, "idle", "")
	_check(Gfx.enable_risk("Android", "forward_plus"), "enabling risk on Android Forward+ succeeds")
	var serialized: Dictionary = Gfx.to_dict()
	_check(bool(serialized.get("risk_enabled", false)), "enable serializes risk_enabled")
	_check(str(serialized.get("risk_boot", "")) == "probing", "enable serializes probing before the profile applies")
	_check(str(serialized.get("risk_last_error", "missing")) == "", "enable clears the previous error")
	Gfx.confirm_risk_probe()
	_check(str(Gfx.to_dict().get("risk_boot", "")) == "proven", "confirming the probe proves the boot")

	_reset_risk(false, "idle", "")
	_check(Gfx.enable_risk("Android", "mobile"), "enabling risk while Mobile runs is allowed")
	_check(str(Gfx.to_dict().get("risk_boot", "")) == "idle", "Mobile never arms a probe")

	_reset_risk(true, "proven", "previous revert")
	Gfx.disable_risk()
	_check(not Gfx.risk_enabled, "disable turns the switch off")
	_check(str(Gfx.risk_boot) == "idle", "disable returns the boot state to idle")
	_check(str(Gfx.risk_last_error) == "previous revert", "disable keeps the previous error explanation")

	_reset_risk(true, "probing", "")
	Gfx.mark_renderer_ready()
	_check(str(Gfx.risk_boot) == "proven", "reaching the editor proves a probing boot")


# -------------------------------------------------------------------------
# Risk-aware profiles and capabilities
# -------------------------------------------------------------------------

const PROFILE_KEYS := ["msaa", "taa", "ssao", "ssil", "ssr", "glow", "volumetric_fog",
	"shadow_quality", "shadow_distance", "shadow_splits", "scale_3d", "max_fps"]


func _snapshot_quality() -> Dictionary:
	return {
		"msaa": Gfx.msaa,
		"taa": Gfx.taa,
		"ssao": Gfx.ssao,
		"ssil": Gfx.ssil,
		"ssr": Gfx.ssr,
		"glow": Gfx.glow,
		"volumetric_fog": Gfx.volumetric_fog,
		"shadow_quality": Gfx.shadow_quality,
		"shadow_distance": Gfx.shadow_distance,
		"shadow_splits": Gfx.shadow_splits,
		"scale_3d": Gfx.scale_3d,
		"max_fps": Gfx.max_fps,
	}


func _restore_quality(state: Dictionary) -> void:
	for key in state.keys():
		Gfx.set(key, state[key])


func _apply_stored_maximum() -> void:
	Gfx.msaa = 3
	Gfx.taa = true
	Gfx.ssil = true
	Gfx.ssr = true
	Gfx.volumetric_fog = true
	Gfx.shadow_quality = 3
	Gfx.shadow_distance = 100.0
	Gfx.shadow_splits = 4
	Gfx.scale_3d = 1.0
	Gfx.max_fps = 120


func _same_profile(a: Dictionary, b: Dictionary) -> bool:
	for key in PROFILE_KEYS:
		if a.get(key) != b.get(key):
			return false
	return true


func _test_risk_profile() -> void:
	print("GRAPHICS STEP: risk-aware profile")
	var saved := _snapshot_quality()
	_apply_stored_maximum()

	var clamped: Dictionary = Gfx.risk_profile("Android", "forward_plus", false)
	_check(not bool(clamped["taa"]), "the clamped profile keeps TAA off")
	_check(not bool(clamped["ssil"]), "the clamped profile keeps SSIL off")
	_check(not bool(clamped["ssr"]), "the clamped profile keeps SSR off")
	_check(not bool(clamped["volumetric_fog"]), "the clamped profile keeps fog off")
	_check(int(clamped["msaa"]) <= 1, "the clamped profile caps MSAA at 2x")
	_check(float(clamped["scale_3d"]) <= 0.85, "the clamped profile caps 3D scale at 85%")
	_check(int(clamped["shadow_quality"]) <= 2, "the clamped profile caps shadows at High")
	_check(float(clamped["shadow_distance"]) <= 40.0, "the clamped profile caps shadow distance at 40 m")
	_check(int(clamped["shadow_splits"]) <= 2, "the clamped profile caps cascades at 2")
	_check(int(clamped["max_fps"]) <= 60, "the clamped profile caps FPS at 60")

	var unlocked: Dictionary = Gfx.risk_profile("Android", "forward_plus", true)
	_check(_same_profile(unlocked, _snapshot_quality()), "the risk-on profile returns the stored maximum values")
	_check(bool(unlocked["taa"]) and bool(unlocked["ssil"]) and bool(unlocked["ssr"]) and bool(unlocked["volumetric_fog"]), "the risk-on profile keeps high-end effects on")
	_check(int(unlocked["msaa"]) == 3, "the risk-on profile allows 8x MSAA")
	_check(float(unlocked["scale_3d"]) == 1.0, "the risk-on profile allows a full 3D scale")
	_check(int(unlocked["shadow_quality"]) == 3, "the risk-on profile allows Ultra shadows")
	_check(float(unlocked["shadow_distance"]) == 100.0, "the risk-on profile allows 100 m shadows")
	_check(int(unlocked["shadow_splits"]) == 4, "the risk-on profile allows 4 cascades")
	_check(int(unlocked["max_fps"]) == 120, "the risk-on profile allows 120 fps")

	var desktop_on: Dictionary = Gfx.risk_profile("Linux", "forward_plus", true)
	var desktop_off: Dictionary = Gfx.risk_profile("Linux", "forward_plus", false)
	_check(_same_profile(desktop_on, desktop_off), "desktop Forward+ is identical in both risk states")
	_check(_same_profile(desktop_on, _snapshot_quality()), "desktop Forward+ keeps the stored values")

	var mobile: Dictionary = Gfx.risk_profile("Android", "mobile", true)
	_check(_same_profile(mobile, _snapshot_quality()), "the Mobile backend keeps the stored values")

	_check(_same_profile(Gfx.safe_forward_plus_profile("Android", "forward_plus", false), clamped), "safe_forward_plus_profile delegates the risk-off profile")
	_check(_same_profile(Gfx.safe_forward_plus_profile("Android", "forward_plus", true), unlocked), "safe_forward_plus_profile delegates the risk-on profile")

	_restore_quality(saved)


func _test_capabilities() -> void:
	print("GRAPHICS STEP: risk-aware capabilities")
	var clamped: Dictionary = Gfx.capabilities_for("forward_plus", "Android", false)
	_check(not bool(clamped.get("taa", true)), "clamped mobile caps keep TAA off")
	_check(not bool(clamped.get("ssil", true)), "clamped mobile caps keep SSIL off")
	_check(not bool(clamped.get("ssr", true)), "clamped mobile caps keep SSR off")
	_check(not bool(clamped.get("volumetric_fog", true)), "clamped mobile caps keep fog off")
	_check(int(clamped.get("msaa_cap", 0)) == 1, "clamped mobile caps keep 2x MSAA")
	_check(float(clamped.get("scale_3d_cap", 1.0)) == 0.85, "clamped mobile caps keep the 85% scale")
	_check(int(clamped.get("shadow_quality_cap", 0)) == 2, "clamped mobile caps keep High shadows")
	_check(int(clamped.get("max_fps_cap", 0)) == 60, "clamped mobile caps keep the 60 fps cap")
	_check(bool(clamped.get("mobile_safe", false)), "clamped mobile caps stay mobile-safe")
	_check(not bool(clamped.get("risk_unlocked", true)), "clamped mobile caps report no risk unlock")

	var unlocked: Dictionary = Gfx.capabilities_for("forward_plus", "Android", true)
	_check(bool(unlocked.get("taa", false)) and bool(unlocked.get("ssil", false)) and bool(unlocked.get("ssr", false)) and bool(unlocked.get("volumetric_fog", false)), "risk unlocks every Forward+ effect")
	_check(int(unlocked.get("msaa_cap", 0)) == 3, "risk unlocks 8x MSAA")
	_check(float(unlocked.get("scale_3d_cap", 0.0)) == 1.0, "risk unlocks the full 3D scale")
	_check(int(unlocked.get("shadow_quality_cap", 0)) == 3, "risk unlocks Ultra shadows")
	_check(int(unlocked.get("max_fps_cap", 0)) == 120, "risk unlocks 120 fps")
	_check(bool(unlocked.get("mobile_safe", false)), "risk still reports the mobile hardware")
	_check(bool(unlocked.get("risk_unlocked", false)), "risk reports the unlock")
	_check(str(unlocked.get("risk_reason", "")) == "High-end effects are on. Stability is not guaranteed.", "risk reports the exact stability reason")

	var desktop_on: Dictionary = Gfx.capabilities_for("forward_plus", "Linux", true)
	var desktop_off: Dictionary = Gfx.capabilities_for("forward_plus", "Linux", false)
	_check(desktop_on == desktop_off, "desktop capabilities are identical in both risk states")
	var mobile_backend: Dictionary = Gfx.capabilities_for("mobile", "Android", true)
	_check(not bool(mobile_backend.get("risk_unlocked", true)), "the Mobile backend reports no Forward+ unlock")
