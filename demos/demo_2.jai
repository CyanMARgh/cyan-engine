#import,dir "../core";
#import "Basic"()(MEMORY_DEBUGGER = true);
#import "Math";
#import "GL";

main :: () {
	defer report_memory_leaks();
	init_resources(); defer deinit_resources();
	init_default_graphics(); defer deinit_default_graphics();

	shader_show_texture := compile_shader_vf(SRC_VERT_SCREEN_SPACE, SRC_FRAG_SHOW_TEXTURE);
	defer deinit(*shader_show_texture);
	test_texture := load_texture_from_file("res/input_texture.png");
	defer deinit(*test_texture);
	sampler := make_test_sampler();

	glEnable(GL_CULL_FACE);
	for window_cycle() {
		for Events if it.type == {
			case .KEY; using it.key_event;
			if type == .PRESS ifx keycode == {
				case GLFW_KEY_ESCAPE; exit();
				case #char"P"; screenshot();
			}
		}
		glClearColor(.15, .08, .08, 1);
		glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

		use(*shader_show_texture);
			bind_sampler(0, test_texture);
			glBindSampler(0, sampler.id);
		draw_empty_mesh(6);
		check_gl_error();
	}
}

SRC_VERT_SCREEN_SPACE :: #string GLSL
	out vec2 uv;
	void main() {
		float points[12] = float[12](0, 0, 1, 1, 0, 1, 0, 0, 1, 0, 1, 1);
		vec2 _uv = vec2(points[gl_VertexID << 1], points[(gl_VertexID << 1) | 1]);
		uv = vec2(_uv.x, 1 - _uv.y);
		gl_Position = vec4(_uv * 2 - 1, 0, 1);
	}
GLSL
SRC_FRAG_SHOW_TEXTURE :: #string GLSL
	layout(binding = 0) uniform sampler2D u_color;
	in vec2 uv;
	out vec4 o_color;
	void main() {
		o_color = texture(u_color, uv);
	}
GLSL