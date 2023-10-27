Text_Painter :: struct {
	ssbo_characters : SSBO_Dynamic(Character_GPU);
	ssbo_char_groups : SSBO_Dynamic(Char_Group);
	font : Font;
}

init_buffers :: (using text_painter : *Text_Painter, max_points : u32) {
	ssbo_characters = make_ssbo_dynamic(Character_GPU, max_points);
	ssbo_char_groups = make_ssbo_dynamic(Char_Group, max_points);
}
deinit :: (using text_painter : *Text_Painter) {
	deinit(*ssbo_characters);
	deinit(*ssbo_char_groups);
}

draw_simple :: (using text_painter : *Text_Painter) {
	bind_sampler(0, font.atlas);
	bind(0, font.ssbo_char_sizes);
	chars_count := commit(*ssbo_characters);
	bind(1, ssbo_characters);
	commit(*ssbo_char_groups);
	bind(2, ssbo_char_groups);

	draw_empty_mesh(6 * chars_count);
}

// scale only by Y
// TODO cut letters that not fits in rect
// TODO multiple lines

//TODO line gap at font generation stage
get_scaling :: (using font : Font, row_size : float) -> factor:float, offset:float {
	FACTOR := row_size / (low_point - high_point);
	OFFSET := -high_point * FACTOR;

	// print("%, %\n", FACTOR, OFFSET);
	return FACTOR, OFFSET;
}
measure_line :: (using font : Font, row_size : float, text : string) -> length:float {
	FACTOR := get_scaling(font, row_size);
	return measure_line(font, text) * FACTOR;
}
//todo add x gap maybe
measure_line :: (using font : Font, text : string) -> length:float {
	offset_x := 0.;
	most_right := 0.;
	// most_left := 100000.;
	for codepoint : iterate(text) {
		char, ok := table_find(*font.char_map, codepoint);
		if !ok continue;
		most_right = max(most_right, offset_x + char.xoff + char.width);
		// most_left = min(most_left, offset_x + char.xoff);
		offset_x += char.advance;
	}
	// print("ml = %\n", most_left);
	return most_right;
}


write_line_base :: (using text_painter : *Text_Painter, text : string) {
	offset_x := 0.;
	for codepoint : iterate(text) { 
		char, ok := table_find(*font.char_map, codepoint);
		if !ok continue;

		actual_size  := Vector2.{xx char.width, xx char.height};
		glyph_offset := Vector2.{xx char.xoff, xx char.yoff};

		left_top := Vector2.{offset_x, 0} + glyph_offset;
		right_bottom := left_top + actual_size;

		push(*ssbo_characters, .{left_top, right_bottom, char.id_in_bitmap});
		offset_x += char.advance;
	}
}
write_line_from_corner :: (using text_painter : *Text_Painter, text : string, left_top : Vector2, row_size : float, color : Vector3, layer : u32) {
	to_depth :: (uz : u32) -> float {
		z := (uz + 1) * .0001 + .1;
		zFar, zNear := 100., .1; 
		return -(zFar + zNear - (2.0 * zNear * zFar) / z) / (zFar - zNear);
	}
	write_line_base(text_painter, text);	

	FACTOR, OFFSET := get_scaling(font, row_size);	
	push(*ssbo_char_groups, .{
		Matrix4.{
			FACTOR, 0, 0, 0,
			0, FACTOR, 0, 0,
			0, 0, FACTOR, 0,
			left_top.x, left_top.y + OFFSET, 0, 1
		} 
		* 
		Matrix4.{
			2. / backend_state.window_metrics.width, 0, 0, 0,
			0, -2. / backend_state.window_metrics.height, 0, 0,
			0, 0, 1, 0,
			-1, 1, to_depth(layer), 1			
		},
		color,
		xx ssbo_characters.cpu_buffer.count
	});
}
write_line_in_rect :: (using text_painter : *Text_Painter, text : string, zone : Rect, color : Vector3, layer : u32) {
	write_line_from_corner(text_painter, text, zone.left_top, zone.bottom - zone.top, color, layer);
}

VERT_TEXT_QUAD :: #run incl(UBO_SCREEN_METRICS, #string GLSL
	layout(std430, binding = 0) buffer ssbo_glyph_sizes {
		vec2 u_glyph_sizes[];
	};
	struct Character {
		vec2 left_top;
		vec2 right_bottom;
		uint char_id;
	};
	layout(std430, binding = 1) buffer ssbo_characters {
		uint u_characters_count;
		Character u_characters_gpu[];
	};
	struct Char_Group {
		mat4 transform;
		vec3 color;
		uint end;
	};
	layout(std430, binding = 2) buffer ssbo_character_groups {
		uint u_character_groups_count;
		Char_Group u_character_groups[];
	};

	Char_Group get_char_group(uint character_id) {
		int i = 0;
		while(i + 1 < u_character_groups_count && character_id >= u_character_groups[i].end) i += 1;
		return u_character_groups[i];
	}

	out vec2 vo_uv;
	out vec3 vo_color;
	flat out uint vo_layer;

	void main() {
		uint character_id = gl_VertexID / 6;
		uint vertex_id = gl_VertexID % 6;
		Character character = u_characters_gpu[character_id];
		float points[12] = float[12](0, 0, 0, 1, 1, 1, 0, 0, 1, 1, 1, 0);
		vec2 p = vec2(points[vertex_id << 1], points[(vertex_id << 1) | 1]);
		vec4 P = vec4(mix(character.left_top, character.right_bottom, p), 0, 1);

		Char_Group char_group = get_char_group(character_id);
	
		gl_Position = char_group.transform * P;
		vec2 uv = p;
		uv *= u_glyph_sizes[character.char_id];

		vo_uv = uv;
		// vo_color = character.color;
		vo_color = char_group.color;
		vo_layer = character.char_id;
	}
GLSL);
FRAG_TEXT_QUAD :: #run incl(UBO_TIME_INFO, #string GLSL
	layout (binding = 0) uniform sampler2DArray u_text_atlas;

	in vec2 vo_uv;
	in vec3 vo_color;
	flat in uint vo_layer;

	out vec4 o_color;
	void main() {
		float mapval = texture(u_text_atlas, vec3(vo_uv, float(vo_layer))).x;
		// classic
		o_color = vec4(
			vo_color,
			mapval
		);

		//sdf
		// o_color = vec4(
		// 	mix(vec3(0), vo_color, smoothstep(.49, .51, mapval)), 
		// 	smoothstep(.44, .47, mapval)
		// );

		//quad
		// o_color = vec4(vo_color, 1);
	}
GLSL);

#scope_file
Character_GPU :: struct {
	a_left_top : Vector2 #align 8;
	a_right_bottom : Vector2 #align 8;
	a_char_id : u32;
}
Char_Group :: struct {
	a_transform : Matrix4 #align 16;
	a_color : Vector3 #align 16;
	end : u32;	
}
