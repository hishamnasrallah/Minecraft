extends RefCounted


func test_bench() -> String:
	var w := WorldData.new(424242)
	var t := Time.get_ticks_usec()
	for dx in range(-2, 3):
		for dz in range(-2, 3):
			w.ensure_chunk(Vector2i(dx, dz))
	print("BENCH generate per chunk: %.1f ms" % ((Time.get_ticks_usec() - t) / 25000.0))
	# like chunk_manager's worker jobs: a fresh WorldData (empty climate cache) per chunk
	t = Time.get_ticks_usec()
	for dx in range(5, 10):
		for dz in range(-2, 3):
			WorldData.new(424242).ensure_chunk(Vector2i(dx, dz))
	print("BENCH generate per chunk, fresh world each: %.1f ms" % ((Time.get_ticks_usec() - t) / 25000.0))
	# breakdown on a warm climate cache
	var k := Vector2i(0, 0)
	var rock_tops := PackedInt32Array()
	rock_tops.resize(256)
	for lx in 16:
		for lz in 16:
			rock_tops[lx * 16 + lz] = w.height_at(lx, lz) - 3
	var blk := PackedInt32Array()
	blk.resize(16 * WorldData.H * 16)
	t = Time.get_ticks_usec()
	for i in 10:
		blk = w._paint_blobs(blk, rock_tops, 0, 0)
	print("BENCH blobs %.2f ms" % ((Time.get_ticks_usec() - t) / 10000.0))
	t = Time.get_ticks_usec()
	for i in 10:
		blk = w._paint_ores(blk, rock_tops, 0, 0)
	print("BENCH ores %.2f ms" % ((Time.get_ticks_usec() - t) / 10000.0))
	t = Time.get_ticks_usec()
	for i in 10:
		blk = w._carve_caves(k, blk)
	print("BENCH caves %.2f ms" % ((Time.get_ticks_usec() - t) / 10000.0))
	t = Time.get_ticks_usec()
	for i in 10:
		w.chunks.erase(Vector2i(7, 7))
		w.ensure_chunk(Vector2i(7, 7))
	print("BENCH whole chunk, warm climate %.2f ms" % ((Time.get_ticks_usec() - t) / 10000.0))
	t = Time.get_ticks_usec()
	for i in 10:
		w._columns.erase(k)
		w.column_info(k)
	print("BENCH column_info %.2f ms" % ((Time.get_ticks_usec() - t) / 10000.0))
	var surf := 0
	for x in 16:
		for z in 16:
			surf += w.top_y(x, z)
	print("BENCH average surface y: ", surf / 256.0, "  H=", WorldData.H)
	return ""


func test_bench_mesh() -> String:
	Mesher._static_setup()
	var w := WorldData.new(5)
	for x in range(0, 6):
		for z in range(0, 6):
			w.ensure_chunk(Vector2i(x, z))
	var m := Mesher.new(w)
	var t := Time.get_ticks_usec()
	var n := 0
	var secs_n := 0
	var light_us := 0
	var rows_us := 0
	for x in range(1, 5):
		for z in range(1, 5):
			var k := Vector2i(x, z)
			var hs: Array = ChunkManager.scan_heights(w.chunks[k], Blocks.transparent)
			var want := []
			for s in range(maxi(int(hs[0]) - 6, 0) / Mesher.SEC, int(hs[1]) / Mesher.SEC + 1):
				want.append(s)
			m.max_y = mini(int(hs[1]) + 1, WorldData.H - 1)
			var tl := Time.get_ticks_usec()
			m.compute_light(k, want[0] * Mesher.SEC, mini(WorldData.H, want[-1] * Mesher.SEC + Mesher.SEC))
			light_us += Time.get_ticks_usec() - tl
			tl = Time.get_ticks_usec()
			for s in want:
				m._mesh_rows(k, s * Mesher.SEC, mini(WorldData.H, s * Mesher.SEC + Mesher.SEC))
			rows_us += Time.get_ticks_usec() - tl
			n += 1
			secs_n += want.size()
	print("BENCH mesh per chunk: %.1f ms (%.1f sections each): light %.1f ms, faces %.1f ms" % [(Time.get_ticks_usec() - t) / 1000.0 / n, float(secs_n) / n, light_us / 1000.0 / n, rows_us / 1000.0 / n])
	return ""
