class_name VNoise
## Hash-based value noise. Every function matches world.py bit for bit, so a seed
## gives exactly the same world in the Python and the Godot versions.


static func hash2(x: int, z: int, seed: int) -> float:
	var n: int = (x * 374761393 + z * 668265263 + seed * 1442695041) & 0xFFFFFFFF
	n = ((n ^ (n >> 13)) * 1274126177) & 0xFFFFFFFF
	return float(n ^ (n >> 16)) / 4294967295.0


static func hash3(x: int, y: int, z: int, seed: int) -> float:
	var n: int = (x * 374761393 + y * 1103515245 + z * 668265263 + seed * 1442695041) & 0xFFFFFFFF
	n = ((n ^ (n >> 13)) * 1274126177) & 0xFFFFFFFF
	return float(n ^ (n >> 16)) / 4294967295.0


static func _smooth(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


static func value_noise(x: float, z: float, seed: int) -> float:
	var x0: int = floori(x)
	var z0: int = floori(z)
	var tx := _smooth(x - x0)
	var tz := _smooth(z - z0)
	var a := hash2(x0, z0, seed)
	var b := hash2(x0 + 1, z0, seed)
	var c := hash2(x0, z0 + 1, seed)
	var d := hash2(x0 + 1, z0 + 1, seed)
	var top := a + (b - a) * tx
	var bottom := c + (d - c) * tx
	return top + (bottom - top) * tz


static func value_noise3(x: float, y: float, z: float, seed: int) -> float:
	var x0: int = floori(x)
	var y0: int = floori(y)
	var z0: int = floori(z)
	var tx := _smooth(x - x0)
	var ty := _smooth(y - y0)
	var tz := _smooth(z - z0)
	var e00 := _lerp(hash3(x0, y0, z0, seed), hash3(x0, y0, z0 + 1, seed), tz)
	var e01 := _lerp(hash3(x0, y0 + 1, z0, seed), hash3(x0, y0 + 1, z0 + 1, seed), tz)
	var e10 := _lerp(hash3(x0 + 1, y0, z0, seed), hash3(x0 + 1, y0, z0 + 1, seed), tz)
	var e11 := _lerp(hash3(x0 + 1, y0 + 1, z0, seed), hash3(x0 + 1, y0 + 1, z0 + 1, seed), tz)
	return _lerp(_lerp(e00, e01, ty), _lerp(e10, e11, ty), tx)


static func _lerp(a: float, b: float, t: float) -> float:
	return a + (b - a) * t


static func cave_density(x: int, y: int, z: int, seed: int) -> float:
	var a := value_noise3(x / 14.0, y / 9.0, z / 14.0, seed + 300) - 0.5
	var b := value_noise3(x / 14.0, y / 9.0, z / 14.0, seed + 600) - 0.5
	return a * a + b * b


static func fbm(x: float, z: float, seed: int, octaves: int = 4) -> float:
	var total := 0.0
	var amp := 1.0
	var freq := 1.0
	var norm := 0.0
	for i in octaves:
		total += value_noise(x * freq, z * freq, seed + i * 101) * amp
		norm += amp
		amp *= 0.5
		freq *= 2.0
	return total / norm
