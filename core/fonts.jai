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
		#insert body;

		char_idx += 1;
		i += byte_len;
	}
}
iterate :: (s : string) -> UTF8_Iterable_String { return .{s}; }

Font :: struct {
	font_raw : string;
	info : Fontinfo;

	line_height := 50;
	quality := 32;
	scale : float;
	max_width, max_height : s32;

	Character :: struct {
		id_in_bitmap : u32;
		width, height, xoff, yoff, advance : s32;
		bitmap : *u8;
	}
	char_map : Table(u32, Character); 

	complete_bitmap : []u8;
	atlas : Texture_3D;
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
	return font, true;
}
add_chars :: (using font : *Font, new_chars : string) {
	for codepoint : iterate(new_chars) {
		char, is_new := find_or_add(*char_map, codepoint);
		if is_new {
			// char.bitmap = get_codepoint_bitmap(
			// 	*info,
			// 	scale, scale,
			// 	xx codepoint,
			// 	*char.width, *char.height, *char.xoff, *char.yoff
			// );
			char.bitmap = get_codepoint_sdf(
				*info,
				scale,
				xx codepoint,
				8, 128, 4,
				*char.width, *char.height, *char.xoff, *char.yoff
			);
			bearing, advance : s32;
			get_codepoint_h_metrics(*info, xx codepoint, *advance, *bearing);
			char.advance = xx(scale * advance);

			max_width = max(max_width, char.width);
			max_height = max(max_height, char.height);
		}
	}
}
move_to_complete_bitmap :: (using altlas : *Font) {
	complete_bitmap = NewArray(max_height * max_width * char_map.count, u8);
	texture_id := 0;
	for * char, codepoint : char_map {
		char.id_in_bitmap = xx texture_id;
		for y : 0..char.height-1 {
			for x : 0..char.width-1 {
				idst := max_width * max_height * texture_id + max_width * y + x;
				isrc := char.width * y + x;
				complete_bitmap[idst] = char.bitmap[isrc];
			}
		}
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
	font.atlas =  make_texture_2d_array(font.max_width, font.max_height, xx font.char_map.count, font.complete_bitmap.data);
	array_free(font.complete_bitmap);

	return font, true;
}

CHARACTERS_LIST_DEFAULT :: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 ,./?`~!@\"#$;:'%^&*()[]{}<>|\\";
CHARACTERS_LIST_RUSSIAN :: "абвгдеёжзийклмнопрстуфхцчшщъыьэюяАБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ";
