#import,dir "../core";
#import "Basic"()(MEMORY_DEBUGGER = true);
#import "Math";
#import "GL";
#import "Random";

main :: () {
	defer report_memory_leaks();
	init_resources(); defer deinit_resources();
	init_default_graphics(); defer deinit_default_graphics();

	MAX_POINTS :: 1_000_000;
	Circle :: struct { point : Vector2; radius : float; color : Vector3; layer : u32; };
	atoms_painter := make_atoms_painter(Circle, MAX_POINTS);
	defer deinit(*atoms_painter);

	shader_circles := compile_shader_vf(SRC_VERT_CIRCLE, SRC_FRAG_CIRCLE);
	defer deinit(*shader_circles);

	layer :u32= 0;
	draw_circle :: (point : Vector2, radius : float, color : Vector3) #expand {
		push(*atoms_painter, .{point, radius, color, layer});
		layer += 1;
	} 

	CIRCLES :: 1_000;
	for i : 0..CIRCLES {
		t := i / cast(float)CIRCLES;
		phi := (t * 2 * PI) * 10;
		r := .2 + t * .7; 
		color := normalize(Vector3.{random_get_within_range(0, 1), random_get_within_range(0, 1), random_get_within_range(0, 1)});
		draw_circle(.{sin(phi) * r, cos(phi) * r}, .03, color);
	}			

	for window_cycle(fps_log_period = 100, print_statistical_fps = true) {
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

		use(*shader_circles);
		glEnable(GL_DEPTH_TEST);

		commit_buffer(*atoms_painter);
		draw(atoms_painter);
	}
}

SRC_VERT_CIRCLE :: #run incl(UBO_SCREEN_METRICS, UBO_CAMERA_PROPERTIES, #string GLSL
	layout (location = 0) in vec2 a_center;
	layout (location = 1) in float a_radius;
	layout (location = 2) in vec3 a_color;
	layout (location = 3) in uint a_layer;

	out struct VO {
		vec3 color;
		vec2 uv;
	} vo;
	float to_depth(float z) {
		const float zFar = 100, zNear = .1; 
		return -(zFar + zNear - (2.0 * zNear * zFar) / z) / (zFar - zNear);
	}
	void main() {
		float points[12] = float[12](0, 0, 1, 1, 0, 1, 0, 0, 1, 0, 1, 1);
		vec2 uv = vec2(points[gl_VertexID << 1], points[(gl_VertexID << 1) | 1]);
		float depth = to_depth(a_layer * .0001 + .1);
		gl_Position = vec4((a_center + (uv * 2 - 1) * a_radius) * vec2(1. * u_height_over_width, 1.), depth, 1);
		vo = VO(a_color, uv);
	}
GLSL);
SRC_FRAG_CIRCLE :: #string GLSL
	in struct VO {
		vec3 color;
		vec2 uv;
	} vo;
	out vec4 o_color;
	void main() {
		o_color = vec4(vo.color, 1);
		vec2 p = vo.uv - .5;
		gl_FragDepth = dot(p, p) < .25 ? gl_FragCoord.z : 2; 
	}
GLSL
