#import,dir "../core";
// #import "Basic"()(MEMORY_DEBUGGER = true);
#import "Basic";
#import "Math";
#import "GL";
#import "Random";

main :: () {
	// defer report_memory_leaks();
	init_resources(); defer deinit_resources();
	init_default_graphics(); defer deinit_default_graphics();

	fb_gbuffer := make_framebuffer(1280, 720, 
		.{"depth", .DEPTH, GL_DEPTH_COMPONENT, GL_DEPTH_COMPONENT, GL_FLOAT},
		.{"color", .COLOR, GL_RGB, GL_RGB, GL_UNSIGNED_BYTE},
		.{"normal", .COLOR, GL_RGB16F, GL_RGB, GL_FLOAT},
		.{"position", .COLOR, GL_RGB16F, GL_RGB, GL_FLOAT}
	);
	defer deinit(*fb_gbuffer);
	fb_ssao_raw := make_framebuffer(backend_state.window_metrics.size, 
		.{"occlusion_raw", .COLOR, GL_RGB, GL_RGB, GL_UNSIGNED_BYTE},
	);
	defer deinit(*fb_ssao_raw);

	// shader_screen_pass := compile_shader_vf(VERT_SCREEN_QUAD, incl(srcheader(fb_gbuffer), FRAG_SCREEN_SHOW_COLOR));
	// defer deinit(*shader_screen_pass);
	shader_default := compile_shader_vf(VERT_DEFAULT, incl(dstheader(fb_gbuffer), FRAG_EXTENDED)); defer deinit(*shader_default);
	shader_raymarched := compile_shader_vf(VERT_CUBE, incl(dstheader(fb_gbuffer), FRAG_RAYMARCHED)); defer deinit(*shader_raymarched);

	shader_ssao := compile_shader_vf(VERT_SCREEN_QUAD, incl(srcheader(fb_gbuffer), FRAG_SSAO)); defer deinit(*shader_ssao);
	shader_blur := compile_shader_vf(VERT_SCREEN_QUAD, incl(srcheaders(fb_gbuffer, fb_ssao_raw), FRAG_BLUR)); defer deinit(*shader_blur);

	noise_texture := make_noise_texture(4, 4);
	defer deinit(*noise_texture);
	loaded_assets, root := load_assets("./res/helmet/DamagedHelmet.gltf");
	defer deinit(*loaded_assets);

	draw_cube_base :: () {
		set_model_transform(graphics_state.scene_translation);
		draw_empty_mesh(36);
	}

	glEnable(GL_CULL_FACE);
	graphics_state.default_camera = .{.{yaw = 0.440064, pitch = -0.023836, position = .{1.826999, -0.00406, 3.104916}, near = 0.1, far = 1000, fow_vertical = 0.942478, screen_size = .{1280, 720}, }, 10, 0.15, 1.570796};
	update_default_camera(true);

	for window_cycle(print_statistical_fps = true, capture_video = true) {
		for Events if it.type == {
			case .KEY; using it.key_event;
			if type == .PRESS ifx keycode == {
				case GLFW_KEY_ESCAPE; exit();
				case #char"P"; screenshot();
				case #char"C"; print("%", graphics_state.default_camera);
			}
			case .MOUSE_BUTTON; using it.mouse_button_event;
			if button == GLFW_MOUSE_BUTTON_LEFT && action == GLFW_PRESS {
				switch_cursor_lock();
			}
		}
		update_default_camera();

		set_size(*fb_gbuffer, backend_state.window_metrics.size);
		ssao_quality := ivec2.{1280, 720};
		set_size(*fb_ssao_raw, ssao_quality);

		bind_as_target(fb_gbuffer);
			clear_target(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT, .[.7, .8, .9, 1], .[0, 0, 0, 0], .[0, 0, 0, 0]);

			glEnable(GL_DEPTH_TEST);
			use(*shader_raymarched);
				for translate(.{1 * cos(current_time * .0), 0, 0}) for scale(1.5) draw_cube_base();
			use(*shader_default);
				draw_node(loaded_assets, root);
			glDisable(GL_DEPTH_TEST);
		bind_default_target();
		bind_as_target(fb_ssao_raw);
			use(*shader_ssao);
				bind_as_source(fb_gbuffer);
				bind_sampler(4, noise_texture);
				set(*shader_ssao, "u_ssao_quality", Vector2.{xx ssao_quality.x, xx ssao_quality.y});
				draw_empty_mesh(6);
		bind_default_target();
			use(*shader_blur);
				set(*shader_blur, "u_ssao_quality", Vector2.{xx ssao_quality.x, xx ssao_quality.y});
				bind_as_sources(fb_gbuffer, fb_ssao_raw);
				draw_empty_mesh(6);
		check_gl_error();

		// use(*shader_screen_pass);
		// 	bind_as_source(fb_gbuffer);
		// draw_empty_mesh(6);

		if(current_time > 10) exit();
	}
}


FRAG_RAYMARCHED :: #run incl(UBO_CAMERA_PROPERTIES, UBO_MAT_M, UBO_TIME_INFO, #string GLSL
	in struct VO {
		vec3 position;
		vec3 normal;
		vec2 uv_0;
	} vo;

	float julia(int L, vec3 p) {
		float t = u_time / 3.0 + .2;

		vec4 c = .5 * vec4(cos(t), cos(t * 1.1), cos(t * 2.3), cos(t * 3.1));
		vec4 z = vec4(p, 0.0);
		vec4 nz;

		float md2 = 1.0;
		float mz2 = dot(z,z);

		for(int i = 0; i < L; i++){
			md2 *= 4 * mz2;
		    nz.x = z.x * z.x - dot(z.yzw, z.yzw);
			nz.yzw = 2.0 * z.x * z.yzw;
			z = nz + c;
			mz2 = dot(z, z);
			if(mz2 > 4) {
				break;
		    }
		}
		return 0.25 * sqrt(mz2 / md2) * log(mz2);
	}
	vec4 sdf(vec3 p) {
		p -= u_center_position;

		// return length(p) - .5;
		return vec4(1., .6, .6, julia(5, p));
	}
	const float epsilon = 1e-4;
	vec3 sdf_normal(vec3 p) {
		const vec2 e = vec2(epsilon, 0);
		float d = sdf(p).w;
		return normalize(vec3(
			sdf(p + e.xyy).w - d,
			sdf(p + e.yxy).w - d,
			sdf(p + e.yyx).w - d
		));
	}
	struct Hit {
		float length;
		bool ok;
		vec3 color;
		vec3 position;
	};
	Hit raymarch(vec3 origin, vec3 dir, float l0) {
		float l = l0;
		vec3 p;
		vec4 h;
		for(int i = 0; i < 50; i++) {
			p = dir * l + origin;
			h = sdf(p);
			if(h.w < epsilon) break;
			if(h.w > 5) return Hit(l, false, vec3(0), vec3(0));
			l += h.w;
		}
		return Hit(l, true, h.rgb, p);
	}

	void main() {
		vec3 origin = u_eye;
		vec3 direction = vo.position - u_eye;
		float l0 = length(direction);
		direction /= l0;

		Hit hit = raymarch(u_eye, direction, l0);
		if(!hit.ok) discard;

		vec3 hit_point = direction * hit.length + origin;
		vec4 P = u_mat_trp * vec4(hit_point, 1);
		P.xyz /= P.w;

		gl_FragDepth = P.z * .5 + .5;

		o_color = hit.color;
		o_normal = sdf_normal(hit.position);
		o_position = hit.position;
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

FRAG_SSAO :: #run incl(UBO_SCREEN_METRICS, gen_kernel(), UBO_CAMERA_PROPERTIES, UBO_TIME_INFO, #string GLSL
	layout(binding = 4) uniform sampler2D u_noise;

	uniform vec2 u_ssao_quality;

	in vec2 vo_uv;
	out vec4 o_color;

	float linearize_depth(float depth) {
		float z = depth * 2 - 1; 
		return (2 * u_near * u_far) / (u_far + u_near - z * (u_far - u_near));	
	}

	void main() {
		vec2 noise_scale = u_ssao_quality / 4; 
		vec2 uv = vo_uv;

		float depth = texture(u_depth, uv).x;
		if(depth >= 1.) {
			o_color = vec4(1);
			return;
		}

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

FRAG_BLUR :: #run incl(UBO_SCREEN_METRICS, UBO_TIME_INFO, #string GLSL
	in vec2 vo_uv;
	out vec4 o_color;
	uniform vec2 u_ssao_quality = vec2(1);

	void main() {
		vec2 uv = vo_uv;
		vec2 texture_factor = 1.0 / u_ssao_quality;

		float kernel[4] = float[4](1, 1, 1, 1);
		const float S = 1. / (4 * 4);

		float occlusion = 0;
		float depth = texture(u_depth_0, uv).x;
		if(depth >= 1.) {
			occlusion = 1;
		} else {
			for(int x = -2; x <= 1; ++x) {
				for(int y = -2; y <= 1; ++y) {
					vec2 offset = (vec2(float(x), float(y)) + .5) * texture_factor;
					float src = texture(u_occlusion_raw_1, vo_uv + offset).x;
					float factor = kernel[x + 2] * kernel[y + 2] * S;
					occlusion += src * factor;
				}
			}
		}
		vec3 color = texture(u_color_0, uv).xyz;


		// if(fract(u_time * .5) < .5) 
		{
			color *= occlusion;
		}
		o_color = vec4(color, 1);
	}
GLSL);

FRAG_GBUF_MSAA :: #run incl(UBO_SCREEN_METRICS, #string GLSL
	vec4 texture_average(sampler2DMS source, vec2 uv, int samples) {
		vec4 result = vec4(0);
		for(int i = 0; i < samples; i++) {
			result += texelFetch(source, ivec2(uv * u_window_size), i);
		}
		return result / samples;
	}
	in vec2 vo_uv;
	void main() {
		#ifdef O_DEPTH
			#ifdef U_SAMPLER2DMS_DEPTH
				o_depth = texture_average(u_depth, vo_uv, SAMPLES).x;
			#endif
		#endif
		#ifdef O_COLOR
			#ifdef U_SAMPLER2DMS_COLOR
				o_color = texture_average(u_color, vo_uv, SAMPLES).xyz;
			#endif
		#endif
		#ifdef O_NORMAL
			#ifdef U_SAMPLER2DMS_NORMAL
				o_normal = texture_average(u_normal, vo_uv, SAMPLES).xyz;
				// TODO just output all vec3/4 or add O_NORMAL_EXT or something
			#endif
		#endif
		#ifdef O_POSITION
			#ifdef U_SAMPLER2DMS_POSITION
				o_position = texture_average(u_position, vo_uv, SAMPLES).xyz;
			#endif
		#endif
		#ifdef O_METALLIC_ROUGHNESS
			#ifdef U_SAMPLER2DMS_METALLIC_ROUGHNESS
				o_metallic_roughness = vec3(texture_average(u_metallic_roughness, vo_uv, SAMPLES).xy, vo_uv.x);
			#endif
		#endif
	}
GLSL);

gen_kernel :: () -> string {
	builder := String_Builder.{allocator = temp};
	KERNEL_SIZE :: 64;
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