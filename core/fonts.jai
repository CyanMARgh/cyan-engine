UTF8_Iterable_String :: struct { s: string; };
for_expansion :: (iterable_str: UTF8_Iterable_String, body: Code, flags: For_Flags) #expand {
	char_idx : s64 = 0;
	i : s64 = 0;
	while i < iterable_str.s.count {
		char, byte_len, result := character_utf8_to_utf32(*iterable_str.s[i], iterable_str.s.count-i);
		if result != .CONVERSION_OK
			break;
		`it	   := char;
		`it_index := char_idx;
		`char_as_str : string = ---;
		char_as_str.count = byte_len;
		char_as_str.data = *(iterable_str.s[i]);
		#insert body;

		char_idx += 1;
		i += byte_len;
	}
}
iterate :: (s : string) -> UTF8_Iterable_String { return .{s}; }

Font :: struct {
	font_raw : string;
	info : Fontinfo;

	line_height := 100;
	sdf_quality := 32;
	scale : float;
	max_bitmap_width, max_bitmap_height : s32;

	Character :: struct {
		id_in_bitmap : u32;
		width, height, xoff, yoff, advance : s32;
		bitmap : *u8;
	}
	char_map : Table(u32, Character); 

	high_point, low_point : s32 = S32_MAX, S32_MIN;
	max_char_height := -1;

	complete_bitmap : []u8;
	char_sizes : []Vector2;
	atlas : Texture_3D;
	ssbo_char_sizes : SSBO;
}
load_font_from_file :: (filepath : string) -> Font, ok:bool {
	using font : Font;
	ok : bool;
	font_raw, ok = read_entire_file(filepath);
	if !ok {
		print("failed to open file: %\n", filepath);
		return font, false;
	}
	if !init_font(*info, font_raw.data, 0) {
		free(font_raw); font_raw = "";
		return font, false;
	}
	scale = scale_for_pixel_height(*info, xx line_height);

	ascent, descent, line_gap : s32;

	return font, true;
}
add_chars :: (using font : *Font, new_chars : string) {
	for codepoint : iterate(new_chars) {
		char, is_new := find_or_add(*char_map, codepoint);
		if is_new {
			char.bitmap = get_codepoint_bitmap(
				*info,
				scale, scale,
				xx codepoint,
				*char.width, *char.height, *char.xoff, *char.yoff
			);
			// char.bitmap = get_codepoint_sdf(
			// 	*info,
			// 	scale,
			// 	xx codepoint,
			// 	8, 128, 4,
			// 	*char.width, *char.height, *char.xoff, *char.yoff
			// );
			bearing, advance : s32;
			get_codepoint_h_metrics(*info, xx codepoint, *advance, *bearing);
			char.advance = xx(scale * advance);

			max_bitmap_width = max(max_bitmap_width, char.width);
			max_bitmap_height = max(max_bitmap_height, char.height);

			if high_point > char.yoff {
				high_point = char.yoff;
				// print("high : %\n", char_as_str);
			}
			if low_point < char.yoff + char.height {
				low_point = char.yoff + char.height;
				// print("low : %\n", char_as_str);
			}
			max_char_height = low_point - high_point;
		}
	}
}
move_to_complete_bitmap :: (using altlas : *Font) {
	complete_bitmap = NewArray(max_bitmap_height * max_bitmap_width * char_map.count, u8);
	char_sizes = NewArray(char_map.count, Vector2);
	texture_id := 0;
	for * char, codepoint : char_map {
		char.id_in_bitmap = xx texture_id;
		for y : 0..char.height-1 {
			for x : 0..char.width-1 {
				idst := max_bitmap_width * max_bitmap_height * texture_id + max_bitmap_width * y + x;
				isrc := char.width * y + x;
				complete_bitmap[idst] = char.bitmap[isrc];
			}
		}
		char_sizes[texture_id] = .{char.width / cast(float)max_bitmap_width, char.height / cast(float)max_bitmap_height};
		free_sdf(char.bitmap, null);
		char.bitmap = null;
		texture_id += 1;
	}
	free(font_raw); font_raw = "";
}
deinit :: (using font : *Font) {
	deinit(*atlas);
	deinit(*char_map);
}

load_font_gpu :: (source_path : string, charsets : ..string) -> Font, ok:bool {
	font, ok := load_font_from_file(source_path);
	if !ok {
		deinit(*font);
		return .{}, false;
	}
	for charsets {
		add_chars(*font, it);
	}
	move_to_complete_bitmap(*font);
	font.atlas =  make_texture_2d_array(font.max_bitmap_width, font.max_bitmap_height, xx font.char_map.count, font.complete_bitmap.data);
	font.ssbo_char_sizes = make_ssbo(font.char_sizes);

	array_free(font.complete_bitmap);
	array_free(font.char_sizes);

	return font, true;
}

CHARACTERS_LIST_DEFAULT :: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 ,./?`~!@\"#$;:'%^&*()[]{}<>|\\+-=";
CHARACTERS_LIST_RUSSIAN :: "абвгдеёжзийклмнопрстуфхцчшщъыьэюяАБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ";
