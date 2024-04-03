#import,dir "../core";
#import "Basic"()(MEMORY_DEBUGGER = true);
#import "Math";
#import "GL";

main :: () {
	defer report_memory_leaks();
	init_resources(); defer deinit_resources();
	init_default_graphics(); defer deinit_default_graphics();

	fb_transparent := make_framebuffer(1280, 720, 
		.{"accum", .COLOR, GL_RGBA16F},
		.{"reveal", .COLOR, GL_R8},
	);
	defer deinit(*fb_transparent);
	fb_solid := make_framebuffer(1280, 720, 
		.{"depth", .DEPTH, GL_DEPTH_COMPONENT32},
		.{"color", .COLOR, GL_RGBA8}
	);
	defer deinit(*fb_solid);

	shader_solid := compile_shader_vf(VERT_DEFAULT, incl(SRC_TARGET_MAIN, FRAG_EXTENDED));
	defer deinit(*shader_solid);
	shader_cube := compile_shader_vf(VERT_CUBE, incl(SRC_TARGET_MAIN, FRAG_EXTENDED));
	defer deinit(*shader_cube);
	shader_transparent := compile_shader_vf(VERT_DEFAULT, incl(dstheader(fb_transparent), FRAG_WEIGHTED_BLENDED));
	defer deinit(*shader_transparent);
	shader_cube_transparent := compile_shader_vf(VERT_CUBE, incl(dstheader(fb_transparent), FRAG_WEIGHTED_BLENDED));
	defer deinit(*shader_cube_transparent);

	shader_screen_pass := compile_shader_vf(VERT_SCREEN_QUAD, incl(srcheaders(fb_solid, fb_transparent), FRAG_SCREEN_PASS));
	defer deinit(*shader_screen_pass);
	// shader_screen_pass := compile_shader_vf(VERT_SCREEN_QUAD, FRAG_SCREEN_SHOW_COLOR_MULTISAMPLED);
	shader_show_texture := compile_shader_vf(VERT_SCREEN_QUAD, incl(defs(), FRAG_SHOW_TEXTURE));
	defer deinit(*shader_show_texture);

	loaded_assets := load_assets("./res/helmet/DamagedHelmet.gltf");
	defer deinit(*loaded_assets);

	material_default : Material;
	send_to_gpu(*material_default);
	defer deinit(*material_default);

	draw_cube_base :: () #expand {
		set_model_transform(graphics_state.scene_translation);
		send_to_gpu(*material_default);
		bind(material_default);
		draw_empty_mesh(36);
	}
	draw_cube :: () #expand {
		use(*shader_cube); 
		draw_cube_base();
	}
	draw_cube_transparent :: () #expand {
		use(*shader_cube_transparent); 
		draw_cube_base();
	}

	graphics_state.default_camera.linear_speed *= .3;

	glEnable(GL_CULL_FACE);
	check_gl_error();
	for window_cycle(print_statistical_fps = true) {
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

		set_size(*fb_transparent, backend_state.window_metrics.size);
		set_size(*fb_solid, backend_state.window_metrics.size);

		bind_as_target(fb_solid);
			glEnable(GL_DEPTH_TEST);
			glDepthFunc(GL_LESS);
			clear_target(GL_DEPTH_BUFFER_BIT, .[.7, .8, .9, 1.]);
			use(*shader_solid);
				for translate(.{1.5, 0, 0}) draw_all_roots(loaded_assets);

			glDisable(GL_DEPTH_TEST);

		bind_as_target(fb_transparent);
			bind(6, fb_solid.textures[0]);

			glEnable(GL_BLEND);
			glBlendFunci(0, GL_ONE, GL_ONE);
			glBlendFunci(1, GL_ZERO, GL_ONE_MINUS_SRC_COLOR);
			glBlendEquation(GL_FUNC_ADD);

			clear_target(GL_DEPTH_BUFFER_BIT, .[ 0,  0,  0,  0], .[ 1,  1,  1,  1]);

			use(*shader_cube_transparent);
				material_default.base_color_factor = .{1, .8, .8, .4};
				for scale(.{.1, 1.5, 1.5}) draw_cube_base();
				material_default.base_color_factor = .{.8, 1, .8, .4};
				for translate(.{.4, 0, 0}) for scale(.{.1, 1.5, 1.5}) draw_cube_base();
				material_default.base_color_factor = .{.8, .8, 1, .4};
				for translate(.{-.4, 0, 0}) for scale(.{.1, 1.5, 1.5}) draw_cube_base();
			for *shader_transparent {
				set("u_alpha_scale", .2);
				for translate(.{-1.5, 0, 0}) draw_all_roots(loaded_assets);
				set("u_alpha_scale", 1.);
			}
			glDisable(GL_BLEND);

		bind_default_target();
			clear_target(GL_DEPTH_BUFFER_BIT, .[ 0,  0,  0,  0]);

			// glEnable(GL_BLEND);
			// glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
	
			use(*shader_screen_pass);
			bind_as_sources(fb_solid, fb_transparent);
				draw_empty_mesh(6);


		// bind_default_target();
		// 	use(*shader_show_texture);
		// 		bind_sampler(0, fb_solid.textures[1]);
		// 		draw_empty_mesh(6);


		// bind_default_target();
		// 	clear_target(GL_DEPTH_BUFFER_BIT, .[ 0,  0,  0,  0]);

			// glDepthFunc(GL_LESS);
			// glDepthMask(GL_TRUE);
			// // glEnable(GL_DEPTH_TEST);

			// use(*shader_solid);
			// 	// for translate(.{2, 0, 0}) 
			// 	draw_node_p(loaded_assets, root);
			// glDepthFunc(GL_ALWAYS);
			// glEnable(GL_BLEND);
			// glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
	
			// use(*shader_screen_pass);
			// 	bind_as_source(fb_transparent);
			// 	draw_empty_mesh(6);

		check_gl_error();
	}
}

FRAG_SHOW_TEXTURE :: #run incl(UBO_CAMERA_PROPERTIES, #string GLSL
	layout(binding = 0) uniform sampler2D u_color;
	in vec2 vo_uv;
	out vec4 o_color;
	void main() {
		#ifdef FIRST_CHANNEL
			o_color = vec4(texture(u_color, vo_uv).xxx, 1);
		#else 
			o_color = texture(u_color, vo_uv);
		#endif
	}
GLSL);

FRAG_WEIGHTED_BLENDED :: #run incl(UBO_SCREEN_METRICS, UBO_MATERIAL, GLTF_TEXTURES, UBO_TIME_INFO, UBO_CAMERA_PROPERTIES, #string GLSL
	layout(binding = 6) uniform sampler2D u_depth;
	uniform float u_alpha_scale = 1;

	in struct VO {
		vec3 position;
		vec3 normal;
		vec2 uv_0;
	} vo;

	float linearize_depth(float depth) {
		float z = depth * 2 - 1; 
		return (2 * u_near * u_far) / (u_far + u_near - z * (u_far - u_near));	
	}

	void main() {
		vec2 uv_0 = vo.uv_0;
		vec4 color = u_base_color_factor;
		if((u_flags & BASE_COLOR) != 0) {
			color *= texture(u_base_color, uv_0);
		}
		color.w *= u_alpha_scale;

		float d0 = linearize_depth(texture(u_depth, (gl_FragCoord.xy) / u_window_size).r);
		float d1 = linearize_depth(gl_FragCoord.z);

		if(d1 > d0) discard;

		float weight = clamp(pow(min(1.0, color.a * 10.0) + 0.01, 3.0) * 1e8 * 
			pow(1.0 - gl_FragCoord.z * 0.9, 3.0), 1e-2, 3e3);

		o_accum = vec4(color.rgb * color.a, color.a) * weight;
		o_reveal = color.a;
	}
GLSL);
FRAG_SCREEN_PASS :: #string GLSL
	uniform float u_time;

	in vec2 vo_uv;
	out vec3 o_color;

	const float EPSILON = 0.00001f;
	bool isApproximatelyEqual(float a, float b) {
		return abs(a - b) <= (abs(a) < abs(b) ? abs(b) : abs(a)) * EPSILON;
	}
	float max3(vec3 v) {
		return max(max(v.x, v.y), v.z);
	}
	vec4 transparent_part(vec2 uv) {
		vec4 color;
		float revealage = texture(u_reveal_1, uv).x;
		if(isApproximatelyEqual(revealage, 1)) return vec4(0);

		vec4 accumulation = texture(u_accum_1, uv);
		if(isinf(max3(abs(accumulation.rgb)))) {
			accumulation.rgb = vec3(accumulation.a);
		}
		vec3 average_color = accumulation.rgb / max(accumulation.a, EPSILON);
		color = vec4(average_color, 1 - revealage);
		return color;		
	}
	
	void main() {
		vec2 uv = vo_uv;

		vec4 tc = transparent_part(uv);
		vec3 sc = texture(u_color_0, uv).xyz;

		o_color = tc.xyz * tc.w + sc * (1 - tc.w);
	}
GLSL