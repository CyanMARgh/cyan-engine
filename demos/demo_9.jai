#import,dir "../core";
#import "Basic"()(MEMORY_DEBUGGER = true);
#import "Math";
#import "GL";
#import "String";
#import "Random";

main :: () {
	defer report_memory_leaks();
	init_resources(); defer deinit_resources();
	init_default_graphics(); defer deinit_default_graphics();

	fb_gbuffer := make_framebuffer(backend_state.window_metrics.size, 
		// .{"depth", .DEPTH, GL_DEPTH_COMPONENT, GL_DEPTH_COMPONENT, GL_FLOAT},
		.{"depth", .COLOR, GL_FLOAT, GL_FLOAT, GL_FLOAT},
		.{"color", .COLOR, GL_RGB, GL_RGB, GL_UNSIGNED_BYTE},
		.{"normal", .COLOR, GL_RGB16F, GL_RGB, GL_FLOAT},
		.{"position", .COLOR, GL_RGB16F, GL_RGB, GL_FLOAT}
	);
	defer deinit(*fb_gbuffer);
	return;
	fb_gbuffer_ms := make_framebuffer(backend_state.window_metrics.size, 
		.{"depth", .DEPTH, GL_DEPTH_COMPONENT, GL_DEPTH_COMPONENT, GL_FLOAT},
		.{"color", .COLOR, GL_RGB, GL_RGB, GL_UNSIGNED_BYTE},
		.{"normal", .COLOR, GL_RGB16F, GL_RGB, GL_FLOAT},
		.{"position", .COLOR, GL_RGB16F, GL_RGB, GL_FLOAT}
		, samples = 4
	);
	defer deinit(*fb_gbuffer_ms);
	fb_ssao_raw := make_framebuffer(backend_state.window_metrics.size, 
		.{"occlusion_raw", .COLOR, GL_RGB, GL_RGB, GL_UNSIGNED_BYTE},
	);
	defer deinit(*fb_ssao_raw);

	// fb_base := make_framebuffer(backend_state.window_metrics.size, 
	// 	.{"depth", .DEPTH, GL_DEPTH_COMPONENT, GL_DEPTH_COMPONENT, GL_FLOAT},
	// 	.{"color", .COLOR, GL_RGB, GL_RGB, GL_UNSIGNED_BYTE},
	// );
	// defer deinit(*fb_base);
	// fb_blurred := make_framebuffer(backend_state.window_metrics.size, 
	// 	.{"color", .COLOR, GL_RGB, GL_RGB, GL_UNSIGNED_BYTE},
	// );
	// defer deinit(*fb_blurred);
	dstheader_gbuffer := dstheader(fb_gbuffer);

	shader_cube := compile_shader_vf(SRC_VERT_CUBE, incl(dstheader_gbuffer, SRC_FRAG_EXTENDED)); defer deinit(*shader_cube);
	shader_default := compile_shader_vf(SRC_VERT_DEFAULT, incl(dstheader_gbuffer, SRC_FRAG_EXTENDED)); defer deinit(*shader_default);
	shader_ssao := compile_shader_vf(
		SRC_VERT_SCREEN_QUAD, 
		incl(srcheader(fb_gbuffer), defs("JUSTCOLOR"), SRC_FRAG_SSAO)
	); 
	shader_blur := compile_shader_vf(SRC_VERT_SCREEN_QUAD, incl(srcheader(fb_ssao_raw), SRC_FRAG_BLUR)); defer deinit(*shader_blur);
	defer deinit(*shader_ssao);

	loaded_assets, root := load_assets("./res/helmet/DamagedHelmet.gltf");
	defer deinit(*loaded_assets);
	noise_texture := make_noise_texture(4, 4);
	defer deinit(*noise_texture);

	default_material : Material;
	send_to_gpu(*default_material);

	graphics_state.default_camera.linear_speed *= .3;

	glEnable(GL_CULL_FACE);
	check_gl_error();

	render_scene :: () #expand {
		glEnable(GL_DEPTH_TEST);
		use(*shader_cube);
			bind(default_material);
			set_model_transform(make_scale_matrix4(.{10, 10, 10}));
			glCullFace(GL_FRONT);
			draw_empty_mesh(36);
			glCullFace(GL_BACK);
		use(*shader_default);
			draw_node(loaded_assets, root);
		glDisable(GL_DEPTH_TEST);
	}
	for window_cycle(fps_log_period = 100, print_statistical_fps = true) {
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
		set_size(*fb_gbuffer_ms, backend_state.window_metrics.size);
		set_size(*fb_ssao_raw, backend_state.window_metrics.size);

		bind_as_target(fb_gbuffer);
			glClear(GL_DEPTH_BUFFER_BIT);
			glClearBufferfv(GL_COLOR, 0, float.[ 0,  0,  0,  1].data);
			glClearBufferfv(GL_COLOR, 1, float.[ 0,  0,  0,  1].data);

			render_scene();

		bind_as_target(fb_gbuffer_ms);
			glClear(GL_DEPTH_BUFFER_BIT);
			glClearBufferfv(GL_COLOR, 0, float.[ 0,  0,  0,  1].data);

			render_scene();

		bind_as_target(fb_ssao_raw);
			use(*shader_ssao);
				bind_as_source(fb_gbuffer);
				bind_sampler(4, noise_texture);
				draw_empty_mesh(6);

		bind_default_traget();
			use(*shader_blur);
				bind_as_source(fb_ssao_raw);
				bind_sampler(1, fb_gbuffer.textures[1]);
				// bind_sampler(1, fb_gbuffer_ms.textures[1]);
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
SRC_VERT_CUBE :: #run incl(UBO_CAMERA_PROPERTIES, UBO_MAT_M, VERTICE_INTERFACE_OUT, #string GLSL
	Input_Vertice gen_vertice() {
		vec3 points[8] = vec3[8](
			vec3( 1, -1, -1), vec3( 1, -1,  1),
			vec3(-1, -1,  1), vec3(-1, -1, -1),
			vec3( 1,  1, -1), vec3( 1,  1,  1),
			vec3(-1,  1,  1), vec3(-1,  1, -1)
		);
		vec3 normals[6] = vec3[6](
			vec3( 0, -1,  0),
			vec3( 0,  1,  0),
			vec3( 1,  0,  0),
			vec3( 0,  0,  1),
			vec3(-1,  0,  0),
			vec3( 0,  0, -1)
		);
		int indices[36] = int[36](
			1, 2, 3, 7, 6, 5, 4, 5, 1, 5, 6, 2,
			2, 6, 7, 0, 3, 7, 0, 1, 3, 4, 7, 5,
			0, 4, 1, 1, 5, 2, 3, 2, 7, 4, 0, 7
		);
		vec3 point = points[indices[gl_VertexID]];
		vec3 normal = normals[(gl_VertexID / 3) % 6];
		return Input_Vertice(point, normal, vec2(0));
	}
GLSL);
SRC_FRAG_SSAO :: #run incl(UBO_SCREEN_METRICS, gen_kernel(), UBO_CAMERA_PROPERTIES, UBO_TIME_INFO, #string GLSL
	layout(binding = 4) uniform sampler2D u_noise;

	in vec2 vo_uv;
	out vec4 o_color;

	float linearize_depth(float depth) {
		float z = depth * 2 - 1; 
		return (2 * u_near * u_far) / (u_far + u_near - z * (u_far - u_near));	
	}

	void main() {
		vec2 noise_scale = u_window_size / 4; 
		vec2 uv = vo_uv;

		vec3 frag_pos = texture(u_position, uv).xyz;
		vec3 normal = texture(u_normal, uv).xyz;
		vec3 random_vec = normalize(texture(u_noise, uv * noise_scale).xyz);
		vec3 tangent = normalize(random_vec - normal * dot(random_vec, normal));
		vec3 bitangent = cross(normal, tangent);		
		mat3 TBN = mat3(tangent, bitangent, normal);

		float occlusion = 0;
		int samples_count = kernel_size;
		for(int i = 0; i < samples_count; i++) {
			vec3 offset = TBN * kernel_values[i];
			vec3 sample_pos = frag_pos + offset;

			vec4 P = u_mat_trp * vec4(sample_pos, 1);
			P.xyz /= P.w;
			vec2 Q = abs(P.xy);
			if(max(Q.x, Q.y) > 1) continue;
			P.xyz = P.xyz * .5 + .5;

			float scene_depth = texture(u_depth, P.xy).x;
			float point_depth = linearize_depth(P.z);
			scene_depth = linearize_depth(scene_depth);

			// float range_check = smoothstep(0, 1, kernel_radius / abs(scene_depth - point_depth));
			float range_check = smoothstep(kernel_radius, 0, abs(scene_depth - point_depth));
			occlusion += (scene_depth < point_depth - kernel_bias ? 1. : 0.) * range_check;
		}
		occlusion = 1 - (occlusion / float(samples_count));
		o_color = vec4(vec3(occlusion), 1);
	}
GLSL);

SRC_FRAG_BLUR :: #run incl(UBO_SCREEN_METRICS, UBO_TIME_INFO, #string GLSL
	layout(binding = 1) uniform sampler2D u_color;
	// layout(binding = 1) uniform sampler2DMS u_color;

	const int u_samples = 4;
	vec4 texture_average(sampler2DMS source, vec2 uv) {
		vec2 screen_size = vec2(1280, 720);

		vec4 result = vec4(0);
		for(int i = 0; i < u_samples; i++) {
			result += texelFetch(source, ivec2(uv * screen_size), i);
		}
		return result / u_samples;
	}

	in vec2 vo_uv;
	out vec4 o_color;

	void main() {
		vec2 uv = vo_uv;
		vec2 texture_factor = 1.0 / u_window_size;

		float kernel[4] = float[4](1, 1, 1, 1);
		const float S = 1. / (4 * 4);

		float occlusion = 0;
		for(int x = -2; x <= 1; ++x) {
			for(int y = -2; y <= 1; ++y) {
				vec2 offset = (vec2(float(x), float(y)) + .5) * texture_factor;
				float src = texture(u_occlusion_raw, vo_uv + offset).x;
				float factor = kernel[x + 2] * kernel[y + 2] * S;
				occlusion += src * factor;
			}
		}
		// vec3 color = texture_average(u_color, uv).xyz;
		vec3 color = texture(u_color, uv).xyz;

		if(fract(u_time * .5) < .5) {
			color *= occlusion;
		}
		o_color = vec4(color, 1);
	}
GLSL);

SRC_FRAG_SCREEN_SHOW_COLOR_MULTISAMPLED :: #string GLSL	
		o_color = vec4(texture_average(u_color, uv).xyz, 1);
	}
GLSL

SRC_FRAG_GBUF_MSAA :: #string GLSL
	vec4 texture_average(sampler2DMS source, vec2 uv, int samples) {
		vec2 screen_size = vec2(1280, 720);

		vec4 result = vec4(0);
		for(int i = 0; i < samples; i++) {
			result += texelFetch(source, ivec2(uv * screen_size), i);
		}
		return result / samples;
	}
	void main() {
		#ifdef O_DEPTH
			#ifdef U_SAMPLER2D_DEPTH
				o_depth = texture_average(u_depth, SAMPLES);
			#endif
		#endif
		#ifdef O_COLOR
			#ifdef U_SAMPLER2D_COLOR
				o_color = texture_average(u_color, SAMPLES);
			#endif
		#endif
		#ifdef O_NORMAL
			#ifdef U_SAMPLER2D_NORMAL
				o_normal = texture_average(u_normal, SAMPLES);
			#endif
		#endif
		#ifdef O_POSITION
			#ifdef U_SAMPLER2D_POSITION
				o_position = texture_average(u_position, SAMPLES);
			#endif
		#endif
	}
GLSL


gen_kernel :: () -> string {
	builder := String_Builder.{allocator = temp};
	KERNEL_SIZE :: 32;
	KERNEL_RADIUS :: 0.7;
	KERNEL_BIAS :: 0.025;

	print_to_builder(*builder, #string GLSL 
	const int kernel_size = %1;
	const float kernel_radius = %2;
	const float kernel_bias = %3;
	vec3 kernel_values[%1] = vec3[%1](
	GLSL, KERNEL_SIZE, KERNEL_RADIUS, KERNEL_BIAS);
	for i : 0..KERNEL_SIZE-1 {
		r := i / cast(float)KERNEL_SIZE;
		r = (r * r) * .9 + .1;
		v := Vector3.{0, 2, 0};
		while length(v) > 1 {
			for * v.component it.* = random_get_within_range(-1, 1);
		}
		v.z = abs(v.z);
		v *= r * KERNEL_RADIUS;
		print_to_builder(*builder, "\tvec3(%, %, %)%", v.x, v.y, v.z, ifx i == KERNEL_SIZE - 1 then ");\n" else ",\n");
	}
	return builder_to_string(*builder, allocator = temp);
}