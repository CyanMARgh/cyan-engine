#import,dir "../core";
#import "Basic"()(MEMORY_DEBUGGER = true);
#import "Math";
#import "GL";

main :: () {
	defer report_memory_leaks();
	init_resources(); defer deinit_resources();
	init_default_graphics(); defer deinit_default_graphics();

	framebuffer := make_framebuffer(1280, 720, 
		.{"depth", .DEPTH, GL_DEPTH_COMPONENT, GL_DEPTH_COMPONENT, GL_FLOAT},
		.{"color", .COLOR, GL_RGB, GL_RGB, GL_UNSIGNED_BYTE},
		.{"normal", .COLOR, GL_RGB16F, GL_RGB, GL_FLOAT},
		.{"position", .COLOR, GL_RGB16F, GL_RGB, GL_FLOAT},
		samples = 8
	);

	shader_default := compile_shader_vf(SRC_VERT_DEFAULT, incl(dstheader(framebuffer), SRC_FRAG_EXTENDED));
	defer deinit(*shader_default);
	// shader_screen_pass := compile_shader_vf(SRC_VERT_SCREEN_QUAD, incl(srcheader(framebuffer), SRC_FRAG_SCREEN_SHOW_COLOR));
	shader_screen_pass := compile_shader_vf(SRC_VERT_SCREEN_QUAD, SRC_FRAG_SCREEN_SHOW_COLOR_MULTISAMPLED);
	defer deinit(*shader_screen_pass);

	loaded_assets, root := load_assets("./res/helmet/DamagedHelmet.gltf");
	defer deinit(*loaded_assets);

	// framebuffer := make_framebuffer(1280, 720, .NORMAL | .POSITION, 8);
	defer deinit(*framebuffer);

	graphics_state.default_camera.linear_speed *= .3;

	glEnable(GL_CULL_FACE);
	check_gl_error();
	for window_cycle() {
		for Events if it.type == {
			case .KEY; using it.key_event;
			if type == .PRESS ifx keycode == {
				case GLFW_KEY_ESCAPE; exit();
				case #char"P"; screenshot();
			}
			case .MOUSE_BUTTON; using it.mouse_button_event;
			if button == GLFW_MOUSE_BUTTON_LEFT && action == GLFW_PRESS {
				switch_cursor_lock();
			}
		}
		update_default_camera();

		bind_as_target(framebuffer);
			glClearBufferfv(GL_COLOR, 0, float.[.7, .8, .9,  1].data);
			glClearBufferfv(GL_COLOR, 1, float.[ 0,  0,  0,  1].data);
			glClearBufferfv(GL_COLOR, 2, float.[ 0,  0,  0,  1].data);
			glClear(GL_DEPTH_BUFFER_BIT);

			glEnable(GL_DEPTH_TEST);
			use(*shader_default);
			draw_node(loaded_assets, root);
		bind_default_target();

		glClear(GL_DEPTH_BUFFER_BIT);
		use(*shader_screen_pass);
			set(*shader_screen_pass, "u_time", backend_state.current_time);
			bind_as_source(framebuffer);
		draw_empty_mesh(6);

		check_gl_error();
	}
}

SRC_VERT_DEFAULT :: #run incl(UBO_CAMERA_PROPERTIES, UBO_MAT_M, VERTICE_INTERFACE_OUT, #string GLSL
	layout (location = 0) in vec3 a_position;
	layout (location = 1) in vec3 a_normal;
	layout (location = 5) in vec2 a_uv_0;
	Input_Vertice gen_vertice() {
		return Input_Vertice(a_position, a_normal, a_uv_0);
	}
GLSL);
SRC_VERT_SCREEN_QUAD :: #string GLSL
	out vec2 vo_uv;
	
	void main() {
		float points[12] = float[12](0, 0, 1, 1, 0, 1, 0, 0, 1, 0, 1, 1);
		vec2 uv = vec2(points[gl_VertexID << 1], points[(gl_VertexID << 1) | 1]);
		vo_uv = uv;
		gl_Position = vec4(uv * 2 - 1, 0, 1);
	}
GLSL
SRC_FRAG_SCREEN_SHOW_COLOR_MULTISAMPLED :: #string GLSL
	layout(binding = 0) uniform sampler2DMS u_depth;
	layout(binding = 1) uniform sampler2DMS u_color;
	layout(binding = 2) uniform sampler2DMS u_normal;
	layout(binding = 3) uniform sampler2DMS u_position;

	in vec2 vo_uv;
	out vec4 o_color;

	const int u_samples = 8;
	vec4 texture_average(sampler2DMS source, vec2 uv) {
		vec2 screen_size = vec2(1280, 720);

		vec4 result = vec4(0);
		for(int i = 0; i < u_samples; i++) {
			result += texelFetch(source, ivec2(uv * screen_size), i);
		}
		return result / u_samples;
	}
	
	void main() {
		vec2 screen_size = vec2(1280, 720);
		vec2 uv = vo_uv;
		vec3 color;

		if(uv.y > .5) {
			uv.y = uv.y * 2 - 1;
			if(uv.x > .5) {
				uv.x = uv.x * 2 - 1;
				color = texture_average(u_color, uv).xyz;
			} else {
				uv.x = uv.x * 2;
				color = texture_average(u_depth, uv).xxx;
			}
		} else {
			uv.y = uv.y * 2;
			if(uv.x > .5) {
				uv.x = uv.x * 2 - 1;
				color = texture_average(u_normal, uv).xyz;
			} else {
				uv.x = uv.x * 2;
				color = texture_average(u_position, uv).xyz;
			}
		}
		o_color = vec4(color, 1);
	}
GLSL
SRC_FRAG_SCREEN_SHOW_COLOR :: #string GLSL
	uniform float u_time;

	in vec2 vo_uv;
	out vec4 o_color;
	
	void main() {
		vec2 screen_size = vec2(1280, 720);
		vec2 uv = vo_uv;
		vec3 color;

		if(uv.y > .5) {
			uv.y = uv.y * 2 - 1;
			if(uv.x > .5) {
				uv.x = uv.x * 2 - 1;
				color = texture(u_color, uv).xyz;
			} else {
				uv.x = uv.x * 2;
				color = texture(u_depth, uv).xxx;
			}
		} else {
			uv.y = uv.y * 2;
			if(uv.x > .5) {
				uv.x = uv.x * 2 - 1;
				color = texture(u_normal, uv).xyz;
			} else {
				uv.x = uv.x * 2;
				color = texture(u_position, uv).xyz;
			}
		}
		o_color = vec4(color, 1);
	}
GLSL