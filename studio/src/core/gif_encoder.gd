extends RefCounted
## GIF89a encoder written in GDScript.
##
## The palette is a 256-colour median-cut table shared by every frame, alpha
## below 0.5 composites to the background, and delays use the centisecond
## accumulator from §17.11 so 24/30 fps stay correct on average even though a
## GIF delay is an integer number of hundredths of a second.

const MIN_DELAY := 1
const MAX_COLORS := 256
const SUPPORTED_FPS := [12, 24, 30]
const WIDTHS := [320, 480, 640, 720]
const FPS_60_REASON := "GIF timing is centisecond-based; 60 fps cannot be represented"


static func can_encode(fps: int) -> bool:
	return fps in SUPPORTED_FPS


static func unsupported_reason(fps: int) -> String:
	if fps == 60:
		return FPS_60_REASON
	return "GIF export supports 12, 24 and 30 fps."


static func widths() -> Array:
	return WIDTHS.duplicate()


## 16:9 height with an even pixel count, as required for the video presets.
static func height_for_width(width: int) -> int:
	var height := int(round(float(width) * 9.0 / 16.0))
	if height % 2 != 0:
		height += 1
	return maxi(2, height)


static func delay_for(index: int, fps: int) -> int:
	var next := int(round(float(index + 1) * 100.0 / float(fps)))
	var current := int(round(float(index) * 100.0 / float(fps)))
	return maxi(MIN_DELAY, next - current)


## Encode frames as a looping (or once-through) GIF. Returns an empty array for
## an unsupported fps, mismatched frame sizes or no frames: callers must treat
## that as a real failure, never as an empty success.
static func encode(frames: Array, fps: int, loop: bool = true) -> PackedByteArray:
	if not can_encode(fps) or frames.is_empty():
		return PackedByteArray()
	var width := 0
	var height := 0
	for raw in frames:
		if not raw is Image:
			return PackedByteArray()
		var image: Image = raw
		if width == 0:
			width = image.get_width()
			height = image.get_height()
		elif image.get_width() != width or image.get_height() != height:
			return PackedByteArray()
	if width < 1 or height < 1:
		return PackedByteArray()
	var palette := _build_palette(frames)
	var background := _nearest_index(palette, 0, 0, 0)
	var out := PackedByteArray()
	out.append_array("GIF89a".to_ascii_buffer())
	_append_u16(out, width)
	_append_u16(out, height)
	out.append(0xF7) # global colour table, 8-bit resolution, 256 entries
	out.append(background)
	out.append(0)
	for color in palette:
		out.append(color.r8)
		out.append(color.g8)
		out.append(color.b8)
	# NETSCAPE loop extension. Count 0 means forever. A once-through GIF omits
	# the extension entirely instead of writing count 1, which some players
	# still treat as a loop.
	if loop:
		out.append(0x21)
		out.append(0xFF)
		out.append(0x0B)
		out.append_array("NETSCAPE2.0".to_ascii_buffer())
		out.append(0x03)
		out.append(0x01)
		_append_u16(out, 0)
		out.append(0x00)
	for index in range(frames.size()):
		var image: Image = frames[index]
		var indices := PackedByteArray()
		indices.resize(width * height)
		for y in range(height):
			for x in range(width):
				var color := image.get_pixel(x, y)
				var palette_index := background
				if color.a >= 0.5:
					palette_index = _nearest_index(palette, color.r8, color.g8, color.b8)
				indices[y * width + x] = palette_index
		var delay := delay_for(index, fps)
		out.append(0x21)
		out.append(0xF9)
		out.append(0x04)
		out.append(0x04) # disposal 1, no transparency (alpha is composited)
		_append_u16(out, delay)
		out.append(background)
		out.append(0x00)
		out.append(0x2C)
		_append_u16(out, 0)
		_append_u16(out, 0)
		_append_u16(out, width)
		_append_u16(out, height)
		out.append(0x00)
		out.append(0x08)
		_write_sub_blocks(out, _lzw_encode(indices, 8))
	out.append(0x3B)
	return out


# -------------------------------------------------------------------------
# Palette
# -------------------------------------------------------------------------

static func _build_palette(frames: Array) -> Array:
	var counts: Dictionary = {}
	var total := 0
	for raw in frames:
		var image: Image = raw
		var pixels := image.get_width() * image.get_height()
		total += pixels
		var step := maxi(1, int(pixels / 8192))
		var i := 0
		while i < pixels:
			var color := image.get_pixel(i % image.get_width(), int(i / image.get_width()))
			var key := 0
			if color.a >= 0.5:
				key = (color.r8 << 16) | (color.g8 << 8) | color.b8
			counts[key] = int(counts.get(key, 0)) + 1
			i += step
	if counts.is_empty():
		counts[0] = 1
	var entries: Array = []
	for key in counts.keys():
		var value := int(key)
		entries.append({
			"r": (value >> 16) & 0xFF,
			"g": (value >> 8) & 0xFF,
			"b": value & 0xFF,
			"count": int(counts[key]),
		})
	var boxes: Array = [entries]
	while boxes.size() < MAX_COLORS:
		var best := -1
		var best_score := 0.0
		for index in range(boxes.size()):
			var box: Array = boxes[index]
			if box.size() < 2:
				continue
			var score := _box_score(box)
			if score > best_score:
				best_score = score
				best = index
		if best < 0:
			break
		var split := _split_box(boxes[best])
		boxes.remove_at(best)
		boxes.append(split[0])
		boxes.append(split[1])
	var palette: Array = []
	for box in boxes:
		var sum_r := 0.0
		var sum_g := 0.0
		var sum_b := 0.0
		var weight := 0.0
		for entry in box:
			var count := float(entry.get("count", 1))
			sum_r += float(entry.get("r", 0)) * count
			sum_g += float(entry.get("g", 0)) * count
			sum_b += float(entry.get("b", 0)) * count
			weight += count
		weight = maxf(1.0, weight)
		palette.append(Color8(int(round(sum_r / weight)), int(round(sum_g / weight)), int(round(sum_b / weight))))
	while palette.size() < MAX_COLORS:
		palette.append(Color8(0, 0, 0))
	return palette


static func _box_score(box: Array) -> float:
	var min_r := 255
	var max_r := 0
	var min_g := 255
	var max_g := 0
	var min_b := 255
	var max_b := 0
	for entry in box:
		min_r = mini(min_r, int(entry.get("r", 0)))
		max_r = maxi(max_r, int(entry.get("r", 0)))
		min_g = mini(min_g, int(entry.get("g", 0)))
		max_g = maxi(max_g, int(entry.get("g", 0)))
		min_b = mini(min_b, int(entry.get("b", 0)))
		max_b = maxi(max_b, int(entry.get("b", 0)))
	return float(maxi(max_r - min_r, maxi(max_g - min_g, max_b - min_b)))


static func _split_box(box: Array) -> Array:
	var min_r := 255
	var max_r := 0
	var min_g := 255
	var max_g := 0
	var min_b := 255
	var max_b := 0
	for entry in box:
		min_r = mini(min_r, int(entry.get("r", 0)))
		max_r = maxi(max_r, int(entry.get("r", 0)))
		min_g = mini(min_g, int(entry.get("g", 0)))
		max_g = maxi(max_g, int(entry.get("g", 0)))
		min_b = mini(min_b, int(entry.get("b", 0)))
		max_b = maxi(max_b, int(entry.get("b", 0)))
	var channel := "r"
	var range_value := max_r - min_r
	if max_g - min_g > range_value:
		channel = "g"
		range_value = max_g - min_g
	if max_b - min_b > range_value:
		channel = "b"
	var sorted := box.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get(channel, 0)) < int(b.get(channel, 0))
	)
	var middle := int(sorted.size() / 2)
	middle = clampi(middle, 1, sorted.size() - 1)
	return [sorted.slice(0, middle), sorted.slice(middle)]


static func _nearest_index(palette: Array, r: int, g: int, b: int) -> int:
	var best := 0
	var best_distance := 1 << 30
	for index in range(palette.size()):
		var color: Color = palette[index]
		var dr := int(color.r8) - r
		var dg := int(color.g8) - g
		var db := int(color.b8) - b
		var distance := dr * dr + dg * dg + db * db
		if distance < best_distance:
			best_distance = distance
			best = index
			if distance == 0:
				break
	return best


# -------------------------------------------------------------------------
# LZW
# -------------------------------------------------------------------------

class BitWriter:
	var bytes := PackedByteArray()
	var buffer := 0
	var count := 0

	func write(code: int, size: int) -> void:
		buffer |= (code & ((1 << size) - 1)) << count
		count += size
		while count >= 8:
			bytes.append(buffer & 0xFF)
			buffer >>= 8
			count -= 8

	func flush() -> void:
		if count > 0:
			bytes.append(buffer & 0xFF)
			buffer = 0
			count = 0


static func _lzw_encode(indices: PackedByteArray, min_code_size: int) -> PackedByteArray:
	var writer := BitWriter.new()
	var clear_code := 1 << min_code_size
	var end_code := clear_code + 1
	var next_code := end_code + 1
	var code_size := min_code_size + 1
	var dictionary: Dictionary = {}
	writer.write(clear_code, code_size)
	if indices.is_empty():
		writer.write(end_code, code_size)
		writer.flush()
		return writer.bytes
	var prefix := int(indices[0])
	for index in range(1, indices.size()):
		var next := int(indices[index])
		var key := prefix * 256 + next
		if dictionary.has(key):
			prefix = int(dictionary[key])
			continue
		writer.write(prefix, code_size)
		if next_code < 4096:
			dictionary[key] = next_code
			next_code += 1
			if next_code == (1 << code_size) and code_size < 12:
				code_size += 1
		else:
			writer.write(clear_code, code_size)
			dictionary.clear()
			next_code = end_code + 1
			code_size = min_code_size + 1
		prefix = next
	writer.write(prefix, code_size)
	writer.write(end_code, code_size)
	writer.flush()
	return writer.bytes


# -------------------------------------------------------------------------
# Byte helpers
# -------------------------------------------------------------------------

static func _append_u16(out: PackedByteArray, value: int) -> void:
	out.append(value & 0xFF)
	out.append((value >> 8) & 0xFF)


static func _write_sub_blocks(out: PackedByteArray, data: PackedByteArray) -> void:
	var offset := 0
	while offset < data.size():
		var size := mini(255, data.size() - offset)
		out.append(size)
		out.append_array(data.slice(offset, offset + size))
		offset += size
	out.append(0)
