extends RefCounted
## Weather state machine, smoothing, rain visuals and save / load.


func test_weather_rain_fades_in_and_out() -> String:
	var w := Weather.new()
	var root := (Engine.get_main_loop() as SceneTree).root
	root.add_child(w)
	w._ready()                              # builds clouds, rain and sound (once)
	w.column_top = func(_x: int, _z: int) -> int: return 20
	var p := Vector3(5, 21, 5)
	w.set_weather("clear")
	for i in 20:
		w.update(0.1, p, 1.0)
	if w.rain_amount != 0.0 or w.sky_dim() > 0.1:
		w.free()
		return "clear sky must not rain: %s" % w.rain_amount
	w.set_weather("rain")
	var before := w.rain_amount
	for i in 30:
		w.update(0.1, p, 1.0)
	var mid := w.rain_amount
	for i in 100:
		w.update(0.1, p, 0.5)
	var err := ""
	var wav := w._sound.stream as AudioStreamWAV
	if wav == null or wav.loop_mode != AudioStreamWAV.LOOP_FORWARD or wav.loop_end < 22050:
		err = "rain sound must be a loop"
	elif not (mid > before and w.rain_amount > 0.99 and w.kind == "rain"):
		err = "rain must fade in: %s %s %s" % [before, mid, w.rain_amount]
	elif w.sky_dim() <= 0.2 or w.sky_dim() > 0.35:
		err = "sky_dim during rain: %s" % w.sky_dim()
	elif w.tint_sky(Color(0.6, 0.8, 1.0)).b >= 1.0:
		err = "tint_sky must darken"
	elif w._rain.multimesh.visible_instance_count < Weather.RAIN_N / 2.0:
		err = "rain streaks: %d" % w._rain.multimesh.visible_instance_count
	if err == "":
		# nothing shown below the column top (a roof at y=40 covering everything)
		w.column_top = func(_x: int, _z: int) -> int: return 40
		w._floor_cache.clear()
		for i in 40:
			w.update(0.1, p, 1.0)
		if w.exposure > 0.5 or w._rain.visible:
			err = "rain under a deep roof: exposure %s visible %s" % [w.exposure, w._rain.visible]
	if err == "":
		w.set_weather("clear")
		for i in 200:
			w.update(0.1, p, 1.0)
		if w.rain_amount != 0.0:
			err = "rain must stop: %s" % w.rain_amount
	w.free()
	return err


func test_weather_changes_by_itself_and_saves() -> String:
	var w := Weather.new()                  # works without being in the tree too
	var seen := {}
	for i in 6000:                          # 100 minutes
		w.update(1.0, Vector3.ZERO, 1.0)
		seen[w.kind] = true
	if seen.size() < 3:
		w.free()
		return "weather never changed: %s" % [seen.keys()]
	w.set_weather("rain")
	w.update(2.0, Vector3.ZERO, 1.0)
	w.set_weather("bogus")
	if w.kind != "rain":
		w.free()
		return "unknown kinds are ignored"
	var d: Dictionary = JSON.parse_string(JSON.stringify(w.save_data()))
	var w2 := Weather.new()
	w2.load_data(d)
	var err := ""
	if w2.kind != "rain" or not is_equal_approx(w2.rain_amount, w.rain_amount) \
			or not is_equal_approx(w2.drift, w.drift) or not is_equal_approx(w2.cloud_amount, w.cloud_amount):
		err = "round trip: %s vs %s" % [w2.save_data(), w.save_data()]
	w2.load_data({})
	if err == "" and w2.kind != "clear":
		err = "empty data means clear"
	w.free()
	w2.free()
	return err


func test_cloud_tile_is_seamless() -> String:
	var w := Weather.new()
	var covered := 0
	for z in Weather.CN:
		for x in Weather.CN:
			if w.cloud_value(x, z) != w.cloud_value(x + Weather.CN, z - Weather.CN):
				w.free()
				return "cloud pattern must repeat every tile"
			if w.cloud_value(x, z) > Weather.COVER_CLEAR:
				covered += 1
	w.free()
	var frac := covered / float(Weather.CN * Weather.CN)
	return "" if frac > 0.05 and frac < 0.4 else "clear-day cover %.2f" % frac
