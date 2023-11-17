#import,dir "../core";
#import "Basic"()(MEMORY_DEBUGGER = true);
#import "Math";
#import "GL";

main :: () {
	defer report_memory_leaks();
	init_resources(); defer deinit_resources();
	init_default_graphics(); defer deinit_default_graphics();

	fb_gbuffer := make_framebuffer(1280, 720, 
		.{"depth", .DEPTH, GL_DEPTH_COMPONENT, GL_DEPTH_COMPONENT, GL_FLOAT},
		.{"color", .COLOR, GL_RGB, GL_RGB, GL_UNSIGNED_BYTE},
		.{"normal", .COLOR, GL_RGB16F, GL_RGB, GL_FLOAT},
		.{"position", .COLOR, GL_RGB16F, GL_RGB, GL_FLOAT},
		samples = 8
	);
	defer deinit(*fb_gbuffer);

	shader_default := compile_shader_vf(VERT_DEFAULT, incl(dstheader(fb_gbuffer), FRAG_EXTENDED));
	defer deinit(*shader_default);
	// shader_screen_pass := compile_shader_vf(VERT_SCREEN_QUAD, incl(srcheader(fb_gbuffer), FRAG_SCREEN_SHOW_COLOR));
	shader_screen_pass := compile_shader_vf(VERT_SCREEN_QUAD, FRAG_SCREEN_SHOW_COLOR_MULTISAMPLED);
	defer deinit(*shader_screen_pass);

	loaded_assets := load_assets("./res/helmet/DamagedHelmet.gltf");
	defer deinit(*loaded_assets);

	// fb_gbuffer := make_framebuffer(1280, 720, .NORMAL | .POSITION, 8);

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

		set_size(*fb_gbuffer, backend_state.window_metrics.size);

		bind_as_target(fb_gbuffer);
			clear_target(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT, .[.7, .8, .9, 1], .[0, 0, 0, 0], .[0, 0, 0, 0]);

			glEnable(GL_DEPTH_TEST);
				use(*shader_default);
					draw_all_roots(loaded_assets);
			glDisable(GL_DEPTH_TEST);

		bind_default_target();
			use(*shader_screen_pass);
				bind_as_source(fb_gbuffer);
			draw_empty_mesh(6);

		check_gl_error();
	}
}

FRAG_SCREEN_SHOW_COLOR_MULTISAMPLED :: #run incl(UBO_SCREEN_METRICS, #string GLSL
	layout(binding = 0) uniform sampler2DMS u_depth;
	layout(binding = 1) uniform sampler2DMS u_color;
	layout(binding = 2) uniform sampler2DMS u_normal;
	layout(binding = 3) uniform sampler2DMS u_position;

	in vec2 vo_uv;
	out vec4 o_color;

	const int u_samples = 8;
	vec4 texture_average(sampler2DMS source, vec2 uv) {
		vec4 result = vec4(0);
		for(int i = 0; i < u_samples; i++) {
			result += texelFetch(source, ivec2(uv * u_window_size), i);
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
GLSL);
FRAG_SCREEN_SHOW_COLOR :: #string GLSL
	uniform float u_time;

	in vec2 vo_uv;
	out vec4 o_color;
	
	void main() {
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