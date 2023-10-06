#import,dir "../core";
#import "Basic"()(MEMORY_DEBUGGER = true);
#import "Math";
#import "GL";
#import "Random";

main :: () {
	// rects();
	points();
}

rects :: () {
	defer report_memory_leaks();
	init_resources(); defer deinit_resources();
	init_default_graphics(); defer deinit_default_graphics();

	MAX_POINTS :: 1000;
	Rect :: struct { left_bottom : Vector2; right_top : Vector2; };
	atoms_painter := make_atoms_painter(Rect, MAX_POINTS);
	defer deinit(*atoms_painter);

	shader_quads_v1 := compile_shader_vf(SRC_VERT_ANY_SIZE_RECTS, SRC_FRAG_WHITE);
	defer deinit(*shader_quads_v1);

	area :: (using rect : Rect) -> float {
		zone := right_top - left_bottom;
		return zone.x * zone.y;
	}
	split_randomly :: (using rect : Rect) -> Rect, Rect {
		if random_get() % 2 {
			m := random_get_within_range(left_bottom.x, right_top.x);
			return .{
				left_bottom, .{m, right_top.y}
			}, .{
				.{m, left_bottom.y},
				right_top				
			};
		} else {
			m := random_get_within_range(left_bottom.y, right_top.y);
			return .{
				left_bottom, .{right_top.x, m}
			}, .{
				.{left_bottom.x, m},
				right_top				
			};
		}
	}
	offset :: (using rect : Rect, delta := 0.005) -> Rect {
		return .{left_bottom + .{delta, delta}, right_top - .{delta, delta}};
	}

	draw_tree :: (painter : *Atoms_Painter(Rect), rect : Rect, depth := 5) {
		if area(rect) < 0 return;
		if depth > 0 {
			rect_a, rect_b := split_randomly(rect);
			draw_tree(painter, offset(rect_a), depth - 1);
			draw_tree(painter, offset(rect_b), depth - 1);
		} else {
			push(painter, rect);
		}
	}

	for window_cycle(fps_log_period = 200) {
		for Events if it.type == {
			case .KEY; using it.key_event;
			if type == .PRESS ifx keycode == {
				case GLFW_KEY_ESCAPE; exit();
			}
		}
		update_default_camera();

		glClearColor(.15, .08, .08, 1);
		glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

		draw_tree(*atoms_painter, .{.{-1, -1}, .{1, 1}}, 10);
		use(*shader_quads_v1);
		draw_simple(*atoms_painter, 6);
	}
}

points :: () {
	MAX_POINTS :: 10000;
	defer report_memory_leaks();

	init_resources(.{800, 600}); defer deinit_resources();
	init_default_graphics(); defer deinit_default_graphics();

	shader_quads_v1 := compile_shader_vf(SRC_VERT_WITH_INSTANCING, SRC_FRAG_WHITE);
	defer deinit(*shader_quads_v1);
	atoms_painter := make_atoms_painter(struct {position : Vector2;}, MAX_POINTS);
	defer deinit(*atoms_painter);

	for window_cycle(fps_log_period = 200) {
		for Events if it.type == {
			case .KEY; using it.key_event;
			if type == .PRESS ifx keycode == {
				case GLFW_KEY_ESCAPE; exit();
				case #char"P"; screenshot();
			}
		}
		update_default_camera();
		glClearColor(.7, .8, .9, 1);
		glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
		for i : 1..MAX_POINTS {
			push(*atoms_painter, .{.{random_get_within_range(-1, 1), random_get_within_range(-1, 1)}});
		}
		use(*shader_quads_v1);
		draw_simple(*atoms_painter, 6);
	}
}

SRC_VERT_WITH_INSTANCING :: #run incl(UBO_SCREEN_METRICS, UBO_CAMERA_PROPERTIES, #string GLSL
	layout (location = 0) in vec2 a_center;
	out vec3 vo_color;
	void main() {
		float points[12] = float[12](0, 0, 1, 1, 0, 1, 0, 0, 1, 0, 1, 1);
		vec2 p = vec2(points[gl_VertexID << 1], points[(gl_VertexID << 1) | 1]);
		float rad = 1.;

		gl_Position = vec4((a_center + p * .02 * rad) * vec2(1. / u_width_over_height, 1.), 0, 1);
		vo_color = rad > 0 ? vec3(1, 1, 1) : vec3(0, 0, 1);
	}
GLSL);
SRC_VERT_ANY_SIZE_RECTS :: #run incl(UBO_SCREEN_METRICS, UBO_CAMERA_PROPERTIES, #string GLSL
	layout (location = 0) in vec2 a_left_bottom;
	layout (location = 1) in vec2 a_right_top;

	out vec3 vo_color;
	void main() {
		float points[12] = float[12](0, 0, 1, 1, 0, 1, 0, 0, 1, 0, 1, 1);
		vec2 p0 = vec2(points[gl_VertexID << 1], points[(gl_VertexID << 1) | 1]);
		vec2 p = mix(a_left_bottom, a_right_top, p0);
		gl_Position = vec4(p * vec2(1. / u_width_over_height, 1.), 0, 1);
		vo_color = vec3(1);
	}
GLSL);
SRC_VERT_NO_INSTANCING :: #run incl(UBO_CAMERA_PROPERTIES, #string GLSL
	uniform vec2 u_center;
	out vec3 vo_color;
	void main() {
		float points[12] = float[12](0, 0, 1, 1, 0, 1, 0, 0, 1, 0, 1, 1);
		vec2 p = vec2(points[gl_VertexID << 1], points[(gl_VertexID << 1) | 1]);
		gl_Position = vec4((u_center + p * .01) * vec2(1. / u_width_over_height, 1.), 0, 1);
		vo_color = vec3(1, 0, 0);
	}
GLSL);
SRC_FRAG_WHITE :: #string GLSL
	in vec3 vo_color;
	out vec4 o_color;
	void main() {
		o_color = vec4(vec3(1), 1);
	}
GLSL

