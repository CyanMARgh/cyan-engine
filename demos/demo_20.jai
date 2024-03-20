#import,dir "../core";
#import "Basic"()(MEMORY_DEBUGGER = true);
#import "Math";
#import "GL";

SCALE ::  2;

main :: () {
	defer report_memory_leaks();
	init_resources(); defer deinit_resources();
	init_default_graphics(); defer deinit_default_graphics();

	fb_reflection := make_framebuffer(backend_state.window_metrics.size / SCALE, 
		.{"depth", .DEPTH, GL_DEPTH_COMPONENT, GL_DEPTH_COMPONENT, GL_FLOAT},
		.{"color", .COLOR, GL_RGB, GL_RGB, GL_UNSIGNED_BYTE}
	);
	defer deinit(*fb_reflection);
	fb_reflection_blured_h := make_framebuffer(backend_state.window_metrics.size / SCALE,
		.{"color", .COLOR, GL_RGB, GL_RGB, GL_UNSIGNED_BYTE}
	);
	defer deinit(*fb_reflection_blured_h);

	// fb_reflection_blured_h := make_framebuffer(backend_state.window_metrics.size, 
	// 	.{"color", .COLOR, GL_RGB, GL_RGB, GL_UNSIGNED_BYTE}
	// );
	// defer deinit(*fb_reflection_blured_h);

	shader_default := compile_shader_vf(VERT_DEFAULT, incl(DSTHEADER_DEFAULT, FRAG_EXTENDED));
	defer deinit(*shader_default);
	// print("VERT_PLANE:\n%\n\nFRAG_PLANE:\n%\n", VERT_PLANE_PP, FRAG_GRID);
	shader_plane := compile_shader_vf(VERT_PLANE, FRAG_GRID);
	defer deinit(*shader_plane);

	shader_blur_h := compile_shader_vf(VERT_SCREEN_QUAD, incl(srcheader(fb_reflection), FRAG_BLUR_H));
	defer deinit(*shader_blur_h);
	// print("VERT_SCREEN_QUAD :\n%\n\n", VERT_SCREEN_QUAD);
	shader_blur_v := compile_shader_vf(VERT_SCREEN_QUAD, incl(srcheader(fb_reflection_blured_h), FRAG_BLUR_V));
	defer deinit(*shader_blur_v);

	// shader_blur_h := compile_shader_vf(VERT_SCREEN_QUAD, incl(srcheaders(fb_reflection), FRAG_BLUR_H));
	// defer deinit(*shader_blur_h);

	loaded_assets := load_assets("./res/helmet/DamagedHelmet.gltf");
	defer deinit(*loaded_assets);

	// default_material : Material;
	// defer deinit(*default_material);
	// default_material.base_color_factor = .{.1, .1, .2, 1};
	// send_to_gpu(*default_material);


	MODEL_COORD :: Vector3.{0, 1, 0};

	glEnable(GL_DEPTH_TEST);
	glEnable(GL_CULL_FACE);
	for window_cycle(print_statistical_fps = true, fps_log_period = 1000) {
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

		set_size(*fb_reflection, backend_state.window_metrics.size / SCALE);
		set_size(*fb_reflection_blured_h, backend_state.window_metrics.size / SCALE);

		bind_as_target(fb_reflection);
			glClearColor(.7, .8, .9, 1);
			glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
			for translate(.{0, -1, 0}) {
				for reflect_y {
					glCullFace(GL_FRONT);			
					for translate(MODEL_COORD) {
						use(*shader_default);
							draw_all_roots(loaded_assets);			
					}
					glCullFace(GL_BACK);
				}
			}

		bind_as_target(fb_reflection_blured_h);
			glClearColor(.7, .8, .9, 1);
			glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
			use(*shader_blur_h);
				bind_as_source(fb_reflection);
				draw_empty_mesh(6);

		bind_default_target();
			glClearColor(.7, .8, .9, 1);
			glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
			use(*shader_blur_v);
				bind_as_source(fb_reflection_blured_h);
				draw_empty_mesh(6);
			glClear(GL_DEPTH_BUFFER_BIT);
			for translate(.{0, -1, 0}) {
				for scale(.{100, 1, 100}) {
					glDisable(GL_DEPTH_TEST);
					glEnable(GL_BLEND);
					glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
					use(*shader_plane);
						set_model_transform(graphics_state.scene_translation);
						draw_empty_mesh(6);				
					glDisable(GL_BLEND);
					glEnable(GL_DEPTH_TEST);
				}
				for translate(MODEL_COORD) {
					use(*shader_default);
						draw_all_roots(loaded_assets);
				}
			}
	}
}

#scope_file

FRAG_GRID :: #run incl(DSTHEADER_DEFAULT, #string GLSL
	in struct VO {
		vec3 position;
		vec3 normal;
		vec2 uv_0;
	} vo;

	void main() {
		vec2 uv_0 = vo.uv_0;
		vec3 base_color = vec3(.1, .1, .2);
		vec3 bright_color = vec3(.8, .8, .7);
		vec2 guv = fract(uv_0 * 100);
		guv = min(1 - guv, guv);
		float h = 1/(1 / guv.x + 1 / guv.y);
		float t = exp(-h * 40);
		vec3 result_color = mix(base_color, bright_color, t);

		#ifdef O_COLOR
			o_color = result_color;
		#else
			#ifdef O_COLOR4
				o_color = vec4(result_color, .7);
			#endif
		#endif
	}
GLSL);

FRAG_SCREEN_SHOW_COLOR :: #string GLSL
	in vec2 vo_uv;
	out vec4 o_color;
	
	void main() {
		vec2 uv = vo_uv;
		vec3 color = texture(u_color, uv).xyz;
		o_color = vec4(color, 1);
	}
GLSL;

FRAG_BLUR_H :: #run incl(UBO_SCREEN_METRICS, #string GLSL
	in vec2 vo_uv;
	out vec4 o_color;

	void main() {
		vec2 uv = vo_uv;
		vec2 source_quality = u_window_size * .5;
		vec2 texture_factor = 1. / source_quality;
		const int N = 20;

		float kernel[N] = float[N](0.000002, 0.000036, 0.000326, 0.001848, 0.007393, 0.022179, 0.05175, 0.096107, 0.144161, 0.176197, 0.176197, 0.144161, 0.096107, 0.05175, 0.022179, 0.007393, 0.001848, 0.000326, 0.000036, 0.000002);

		vec3 result_color = vec3(0);

		for(int x = 0; x < N; ++x) {
			vec2 offset = vec2(float(x) - .5 - N / 2, 0) * texture_factor;
			vec3 src = texture(u_color, vo_uv + offset).xyz;
			result_color += src * kernel[x];
		}

		o_color = vec4(result_color, 1);
	}
GLSL);
FRAG_BLUR_V :: #run incl(UBO_SCREEN_METRICS, #string GLSL
	in vec2 vo_uv;
	out vec4 o_color;

	void main() {
		vec2 uv = vo_uv;
		vec2 source_quality = u_window_size * .5;
		vec2 texture_factor = 1. / source_quality;
		const int N = 20;

		float kernel[N] = float[N](0.000002, 0.000036, 0.000326, 0.001848, 0.007393, 0.022179, 0.05175, 0.096107, 0.144161, 0.176197, 0.176197, 0.144161, 0.096107, 0.05175, 0.022179, 0.007393, 0.001848, 0.000326, 0.000036, 0.000002);

		vec3 result_color = vec3(0);

		for(int i = 0; i < N; ++i) {
			vec2 offset = vec2(0, float(i) - .5 - N / 2) * texture_factor;
			vec3 src = texture(u_color, vo_uv + offset).xyz;
			result_color += src * kernel[i];
		}

		o_color = vec4(result_color, 1);
	}
GLSL);