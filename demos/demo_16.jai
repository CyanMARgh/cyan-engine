#import,dir "../core";
#import "Basic"()(MEMORY_DEBUGGER = true);
#import "Math";
#import "GL";
#import "Hash_Table";
#import "Hash";

UI_Element :: struct {
	type : enum u8 {
		NONE		:: 0;
		BUTTON		:: 1;
		FLOAT_RANGE	:: 2;
	};
	frames_after_press : int;
}
UI_Button :: struct {
	#as using ui_element := UI_Element.{type = .BUTTON};
}
UI_Float_Range :: struct {
	#as using ui_element := UI_Element.{type = .FLOAT_RANGE};
	value_backup : float;
}

Elements_Table :: Table(Source_Code_Location, *UI_Element, scl_hash, scl_cmp);

MAX_POINTS :: 1000;
BUTTON_BASE_COLOR :: #run hex2f3(0x20324d);
BUTTON_UNDER_CURSOR_COLOR :: #run hex2f3(0x2a4c75);
BUTTON_PUSHED_COLOR :: #run hex2f3(0x336caf);
BORDER_COLOR :: #run hex2f3(0x999999);
TEXT_GAP :: 5.;
BORDER_GAP :: 1.;
UI_DEFAULT_ELEMENT_GAP :: 5.;
UI_DEFAULT_ELEMENT_OFFSET :: Vector2.{UI_DEFAULT_ELEMENT_GAP, UI_DEFAULT_ELEMENT_GAP};
UI_DEFAULT_ELEMENT_HEIGHT :: 40.;

scl_hash :: (using loc : Source_Code_Location) -> u32 {
	h123 : [2]int = int.[line_number, character_number];
	return get_hash(h123);
}
scl_cmp :: (loc_1 : Source_Code_Location, loc_2 : Source_Code_Location) -> bool {
	if loc_1.line_number != loc_2.line_number return false;
	if loc_1.character_number != loc_2.character_number return false;
	return loc_1.fully_pathed_filename == loc_2.fully_pathed_filename;
}
color_by_state :: (under_cursor : bool, el : *UI_Element) -> Vector3, Vector3 {
	base := BUTTON_BASE_COLOR;
	aspect := #run hex2f3(0xeeeeee);
	if under_cursor && (pressed_element == null || pressed_element == el) {
		base = BUTTON_UNDER_CURSOR_COLOR;
	}
	if pressed_element == el {
		base = BUTTON_PUSHED_COLOR;
		aspect = #run hex2f3(0xffffff);
	}
	return base, aspect;
}

// target_elements_stack : SBDA(*UI_Element, 10);
// TODO ui_draw_line and so on
// TODO ui_shared_primitive_layer
button_base :: (zone : Rect, text := "", loc := #caller_location) -> bool {
	elptr, new := find_or_add(*elements_table, loc);
	if new {
		elptr.* = New(UI_Button);
	}
	el := elptr.*;
	assert(el.type == .BUTTON);
	using cast(*UI_Button)el;

	is_cursor_over := inside(backend_state.cursor_position, zone);

	if pressed_element == el {
		frames_after_press = min(frames_after_press + 1, 1000);
	}
	if lmb_pressed() {
		if is_cursor_over then pressed_element = el;
	}
	result := false;
	if lmb_released() {
		frames_after_press = 0;
		if pressed_element == el && is_cursor_over {
			result = true;
		}
	}

	base, aspect := color_by_state(is_cursor_over, el);
	ui_draw_rect(zone, BORDER_COLOR);
	content_zone := add_gap(zone, BORDER_GAP);
	ui_draw_rect(content_zone, base);
	ui_draw_line(text, add_gap(content_zone, TEXT_GAP), aspect);
	// print("(1)\n");
	return result;
}
button :: (text := "", loc := #caller_location) -> bool {
	height := UI_DEFAULT_ELEMENT_HEIGHT;
	length := max(measure_line(ui_text_painter.font, height - TEXT_GAP * 2 - BORDER_GAP * 2, text), UI_DEFAULT_ELEMENT_HEIGHT);
	result := button_base(
		.{ui_left_top_current, ui_left_top_current + Vector2.{length + TEXT_GAP * 2 + BORDER_GAP * 2, height}}, 
		text, loc
	);
	ui_left_top_current.y += UI_DEFAULT_ELEMENT_HEIGHT + UI_DEFAULT_ELEMENT_GAP;
	return result;
}
float_range_base :: (zone : Rect, bar_width : float, value : *float, A : float, B : float, fmt : string = "", loc := #caller_location) {
	elptr, new := find_or_add(*elements_table, loc);
	if new {
		elptr.* = New(UI_Float_Range);
	}
	el := elptr.*;
	assert(el.type == .FLOAT_RANGE);
	using cast(*UI_Float_Range)el;

	content_zone := add_gap(zone, BORDER_GAP);
	is_cursor_over := inside(backend_state.cursor_position, content_zone);
	free_length := (content_zone.right - content_zone.left - bar_width);
	bar_offset := free_length * (value.* - A) / (B - A);

	if pressed_element == el {
		frames_after_press = min(frames_after_press + 1, 1000);
	}
	if lmb_pressed() {
		if is_cursor_over {
			pressed_element = el;
			rcpx := backend_state.cursor_position.x - content_zone.left;
			if rcpx < bar_offset || rcpx > bar_offset + bar_width {
				value.* = A + (rcpx - bar_width / 2) * (B - A) / free_length;
			}
			value_backup = value.*;
		} 
	}
	if lmb_down() && el == pressed_element {
		cursor_delta := backend_state.cursor_position.x - backend_state.dragg_start.x;
		value.* = value_backup + cursor_delta * (B - A) / free_length;
	}
	if lmb_released() {
		frames_after_press = 0;
	}

	Clamp(value, A, B);
	bar_offset = free_length * (value.* - A) / (B - A);

	base, aspect := color_by_state(is_cursor_over, el);
	Clamp(*bar_width, 0, zone.right - zone.left);

	ui_draw_rect(zone, BORDER_COLOR);	
	ui_draw_rect(content_zone, base);
	bar_color := ifx fmt then BORDER_COLOR else aspect;
	ui_draw_rect(.{
			.{content_zone.left + bar_offset, content_zone.top}, 
			.{content_zone.left + bar_width + bar_offset, content_zone.bottom}
		}, 
		bar_color
	);
	if fmt {
		ui_draw_line(tprint(fmt, value.*), add_gap(content_zone, TEXT_GAP), aspect);
		// print("(0)\n");
	}
}
float_range :: (value : *float, A : float, B : float, fmt : string = "", loc := #caller_location) {
	height := UI_DEFAULT_ELEMENT_HEIGHT;
	length := height * 8;
	bar_width := height;
	float_range_base(.{ui_left_top_current, ui_left_top_current + .{length, height}}, bar_width, value, A, B, fmt, loc);
}

ui_quads_painter : Atoms_Painter(Rect_Colored);
ui_text_painter : Text_Painter;
ui_shader_quads, ui_shader_text : Shader;

elements_table : Elements_Table;
pressed_element : *UI_Element = null;
ui_left_top_current : Vector2;
ui_primitive_layer : u32;

init_ui :: () {
	ui_shader_quads = compile_shader_vf(VERT_SCREEN_SCALE_RECTS, FRAG_SINGLE_COLOR);
	ui_shader_text = compile_shader_vf(VERT_TEXT_QUAD, FRAG_TEXT_QUAD);

	ui_quads_painter = make_atoms_painter(Rect_Colored, MAX_POINTS);
	init_buffers(*ui_text_painter, MAX_POINTS);
	ui_text_painter.font = load_font_gpu("./res/fonts/cmunrm.ttf", CHARACTERS_LIST_DEFAULT/*, CHARACTERS_LIST_RUSSIAN*/); // ни слова по-русски
}
deinit_ui :: () {
	deinit(*ui_shader_quads);
	deinit(*ui_shader_text);

	deinit(*ui_quads_painter);

	deinit(*ui_text_painter.font);
	deinit(*ui_text_painter);

	for elements_table free(it);
	table_reset(*elements_table);
}

ui_begin :: () {
	ui_primitive_layer = 0;
	ui_left_top_current = UI_DEFAULT_ELEMENT_OFFSET;
}
ui_end :: (draw := true) {
	ui_draw :: () {
		glEnable(GL_DEPTH_TEST);
			use(*ui_shader_quads);
				draw_simple(*ui_quads_painter, 6);
			glEnable(GL_BLEND);
			glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
				use(*ui_shader_text);
					draw_simple(*ui_text_painter);
			glDisable(GL_BLEND);
		glDisable(GL_DEPTH_TEST);
	}
	if lmb_released() {
		pressed_element = null;
	}
	if draw {
		ui_draw();
	}
}

main :: () {
	defer report_memory_leaks();
	init_resources(); defer deinit_resources();
	init_default_graphics(); defer deinit_default_graphics();

	init_ui();
	defer deinit_ui();

	fval := 0.;
	for window_cycle(fps_log_period = 200) {
		for Events {
			if it.type == {
				case .KEY; using it.key_event;
				if type == .PRESS ifx keycode == {
					case GLFW_KEY_ESCAPE; exit();
					case #char"P"; screenshot();
				}
			}
		}
		update_default_camera();
		clear_target_v4(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT, hex2f4(0x1a1b1c));

		ui_begin();
			if button("button #1") print("button #1\n");
			if button("second button") print("button #2\n");
			float_range(*fval, 0, 2, "%");

			// if button_base(.{.{5, 5}, .{200, 50}}, "button #1") print("button #1\n");
			// if button_base(.{.{5, 5}, .{100, 50}}, "btn2") print("button #2\n");
		ui_end();
		// print("(2)\n");
	}	
}

ui_draw_line :: (text : string, zone : Rect, color : Vector3) {
	write_line_in_rect(*ui_text_painter, text, zone, color, ui_primitive_layer);
	ui_primitive_layer += 1;
}

ui_draw_rect :: (r : Rect, color : Vector3) {
	rect := Rect_Colored.{r.left_top, r.right_bottom, color, ui_primitive_layer};
	push(*ui_quads_painter, rect);
	ui_primitive_layer += 1;
}
Rect_Colored :: struct {
	a_left_top : Vector2;
	a_right_bottom : Vector2;
	a_color : Vector3;
	a_layer : u32;
};
VERT_SCREEN_SCALE_RECTS :: #run incl(UBO_SCREEN_METRICS, UBO_CAMERA_PROPERTIES, #string GLSL
	layout (location = 0) in vec2 a_left_bottom;
	layout (location = 1) in vec2 a_right_top;
	layout (location = 2) in vec3 a_color;
	layout (location = 3) in uint a_layer;

	out vec3 vo_color;

	float to_depth(float z) {
		const float zFar = 100, zNear = .1; 
		return -(zFar + zNear - (2.0 * zNear * zFar) / z) / (zFar - zNear);
	}
	float to_depth(uint z) {
		return to_depth((a_layer + 1) * .0001 + .1);
	}
	void main() {
		float points[12] = float[12](0, 0, 1, 1, 0, 1, 0, 0, 1, 0, 1, 1);
		vec2 p0 = vec2(points[gl_VertexID << 1], points[(gl_VertexID << 1) | 1]);
		vec2 p = mix(a_left_bottom, a_right_top, p0);
		p /= u_window_size;
		p = p * 2 - 1;
		#ifndef NOFLIP
		p.y = -p.y;
		#endif
		float depth = to_depth(a_layer);
		gl_Position = vec4(p, depth, 1);
		vo_color = a_color;
	}
GLSL);
FRAG_SINGLE_COLOR :: #string GLSL
	in vec3 vo_color;
	out vec4 o_color;
	void main() {
		o_color = vec4(vo_color, 1);
	}
GLSL
