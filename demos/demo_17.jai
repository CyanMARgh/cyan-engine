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
	init_ui(); defer deinit_ui();

	fb_gbuffer_ms := make_framebuffer(1280, 720, 
		.{"depth", .DEPTH, GL_DEPTH_COMPONENT32},
		.{"color", .COLOR, GL_RGB8},
		.{"normal", .COLOR, GL_RGB16F},
		.{"position", .COLOR, GL_RGB16F},
		.{"metallic_roughness", .COLOR, GL_RGB8},
		.{"emissive", .COLOR, GL_RGB8},
		samples = 1
	);
	defer deinit(*fb_gbuffer_ms);
	ssao_quality := ivec2.{1280, 720};
	fb_ssao_raw := make_framebuffer(backend_state.window_metrics.size, 
		.{"occlusion_raw", .COLOR, GL_R8},
	);
	defer deinit(*fb_ssao_raw);
	fb_ssao_blurred := make_framebuffer(backend_state.window_metrics.size, 
		.{"occlusion", .COLOR, GL_RGB8},
	);
	defer deinit(*fb_ssao_blurred);

	main_target_header := dstheader(fb_gbuffer_ms);
	shader_default := compile_shader_vf(VERT_DEFAULT, incl(main_target_header, FRAG_EXTENDED)); 
	defer deinit(*shader_default);
	shader_raymarched := compile_shader_vf(VERT_CUBE, incl(main_target_header, FRAG_RAYMARCHED)); 
	defer deinit(*shader_raymarched);
	shader_background_cubemap := compile_shader_vf(VERT_SCREEN_CUBE, incl(main_target_header, FRAG_BACKGROUND_CUBEMAP)); 
	defer deinit(*shader_background_cubemap);

	shader_ssao := compile_shader_vf(incldefs("NOFLIP", VERT_SCREEN_QUAD), incl(dstheader(fb_ssao_raw), srcheader(fb_gbuffer_ms), FRAG_SSAO)); 
	defer deinit(*shader_ssao);
	shader_blur := compile_shader_vf(incl(defs("NOFLIP"), VERT_SCREEN_QUAD), incl(srcheaders(fb_gbuffer_ms, fb_ssao_raw), FRAG_BLUR));
	defer deinit(*shader_blur);
	shader_light_pass := compile_shader_vf(incl(defs("NOFLIP"), VERT_SCREEN_QUAD), incl(srcheader(fb_gbuffer_ms), FRAG_LIGHT_PASS));
	defer deinit(*shader_light_pass);

	noise_texture := make_noise_texture(4, 4);
	defer deinit(*noise_texture);
	loaded_assets := load_assets("./res/helmet/DamagedHelmet.gltf");
	defer deinit(*loaded_assets);

	source_cubemap, ok := load_cubemap_from_file("res/yokohama2/", "posx.jpg", "negx.jpg", "posy.jpg", "negy.jpg", "posz.jpg", "negz.jpg");
	assert(ok);
	defer deinit(*source_cubemap);
	BRDF_RESOLUTION :: 128;
	texture_brdf := make_texture_buffer(BRDF_RESOLUTION, BRDF_RESOLUTION, .{GL_RGB8, 0, GL_TEXTURE_2D});
	defer deinit(*texture_brdf);
	{
		shader_prerender := compile_shader_vf(incl(defs("NOFLIP"), VERT_SCREEN_QUAD), FRAG_BRDF);
		defer deinit(*shader_prerender);

		prerender_texture_fbo : u32;
		glGenFramebuffers(1, *prerender_texture_fbo);
		glBindFramebuffer(GL_FRAMEBUFFER, prerender_texture_fbo);
			glViewport(0, 0, BRDF_RESOLUTION, BRDF_RESOLUTION);
			glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, texture_brdf.id, 0);
			for *shader_prerender {
				draw_empty_mesh(6);
			}
		glBindFramebuffer(GL_FRAMEBUFFER, 0);
		glDeleteFramebuffers(1, *prerender_texture_fbo);
	}

	PCM_RESOLUTION :: 256;
	prerendered_cubemap := make_cubemap(PCM_RESOLUTION, PCM_RESOLUTION, true);
	defer deinit(*prerendered_cubemap);
	{
		// shader_prerender := compile_shader_vf(VERT_TO_CUBEMAP, FRAG_SHOW_UV);
		shader_prerender := compile_shader_vf(VERT_TO_CUBEMAP, FRAG_PREFILTER);
		defer deinit(*shader_prerender);

		prerendered_cubemap_fbo : u32;
		glGenFramebuffers(1, *prerendered_cubemap_fbo);
		glBindFramebuffer(GL_FRAMEBUFFER, prerendered_cubemap_fbo);

		max_mml :: 6;
		for mml : 0..max_mml-1 {
			layer_width := PCM_RESOLUTION * pow(.5, xx mml);
			roughness := mml / cast(float)(max_mml-1);
			for i : 0..5 {
				glViewport(0, 0, xx layer_width, xx layer_width);
				glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, xx(GL_TEXTURE_CUBE_MAP_POSITIVE_X + i), prerendered_cubemap.id, xx mml);
				for *shader_prerender {
					set("u_roughness", roughness);
					set("u_part_id", cast(u32)i);
					bind_sampler(0, source_cubemap);
					draw_empty_mesh(6);				
				}
			}
		}


		glBindFramebuffer(GL_FRAMEBUFFER, 0);
		glDeleteFramebuffers(1, *prerendered_cubemap_fbo);
	}

	draw_cube_base :: () {
		set_model_transform(graphics_state.scene_translation);
		draw_empty_mesh(36);
	}

	glEnable(GL_CULL_FACE);
	// graphics_state.default_camera = .{.{yaw = 0.440064, pitch = -0.023836, position = .{1.826999, -0.00406, 3.104916}, near = 0.1, far = 1000, fow_vertical = 0.942478, screen_size = .{1280, 720}, }, 10, 0.15, 1.570796};
	// graphics_state.default_camera = .{.{yaw = 4.493997, pitch = 0.072886, position = .{-4.426746, -0.00406, -1.897735}, near = 0.1, far = 1000, fow_vertical = 0.942478, screen_size = .{1280, 720}, }, 10, 0.15, 1.570796};
	graphics_state.default_camera = .{camera = .{yaw = 4.435211, pitch = 0.088499, position = .{-1.379982, -0.00406, -0.895963}, near = 0.1, far = 1000, fow_vertical = 0.942478, screen_size = .{1280, 720}, }, linear_speed = 10, pitch_limit = 1.570796};
	update_default_camera(true);

	julia_offset := Vector3.{2., 0, 0};
	box_size :: .8;

	for window_cycle(print_statistical_fps = true, capture_video = false) {
		maybe_switch := false;
		for Events if it.type == {
			case .KEY; using it.key_event;
			if type == .PRESS ifx keycode == {
				case GLFW_KEY_ESCAPE; exit();
				case #char"P"; screenshot();
				case #char"C"; print("%\n", graphics_state.default_camera);
			}
			case .MOUSE_BUTTON; using it.mouse_button_event;
			if button == GLFW_MOUSE_BUTTON_LEFT && action == GLFW_PRESS {
				maybe_switch = true;
			}
		}
		update_default_camera();

		set_size(*fb_gbuffer_ms, backend_state.window_metrics.size);
		ssao_quality := ivec2.{1280, 720};
		set_size(*fb_ssao_raw, ssao_quality);

		bind_as_target(fb_gbuffer_ms);
			clear_target(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT, 
				.[.7, .8, .9, 1],
				.[0, 0, 0, 0],
				.[0, 0, 0, 0],
				.[0, 0, 0, 0],
				.[0, 0, 0, 0],
				.[0, 0, 0, 0]
			);
			glCullFace(GL_FRONT);
				use(*shader_background_cubemap);
					bind_sampler(0, source_cubemap);
					draw_empty_mesh(36);
			glCullFace(GL_BACK);

			glEnable(GL_DEPTH_TEST);
			use(*shader_default);
				draw_all_roots(loaded_assets);
			use(*shader_raymarched);
				for translate(julia_offset) for scale(box_size) draw_cube_base();
			glDisable(GL_DEPTH_TEST);
		bind_default_target();
		bind_as_target(fb_ssao_raw);
			use(*shader_ssao);
				bind_as_source(fb_gbuffer_ms);
				bind(4, noise_texture);
				set(*shader_ssao, "u_ssao_quality", Vector2.{xx ssao_quality.x, xx ssao_quality.y});
				draw_empty_mesh(6);
		bind_as_target(fb_ssao_blurred);
			use(*shader_blur);
				set(*shader_blur, "u_ssao_quality", Vector2.{xx ssao_quality.x, xx ssao_quality.y});
				bind_as_sources(fb_gbuffer_ms, fb_ssao_raw);
				draw_empty_mesh(6);
		bind_default_target();
			use(*shader_light_pass);
				bind_as_sources(fb_gbuffer_ms, fb_ssao_raw);
				bind(6, texture_brdf);
				bind_sampler(7, prerendered_cubemap);
				bind(8, fb_ssao_blurred.textures[0]);
				draw_empty_mesh(6);
			clear_target(GL_DEPTH_BUFFER_BIT);
			ui_begin();
				float_range(*julia_offset.x, -4, 4, "x = %");
				float_range(*julia_offset.y, -4, 4, "y = %");
				float_range(*julia_offset.z, -4, 4, "z = %");
			ui_end();
		check_gl_error();

		if maybe_switch && !ui_state.ui_interacted_this_frame switch_cursor_lock();
	}
}

FRAG_RAYMARCHED :: #run incl(UBO_CAMERA_PROPERTIES, UBO_MAT_M, UBO_TIME_INFO, #string GLSL
	in struct VO {
		vec3 position;
		vec3 normal;
		vec2 uv_0;
	} vo;

	const float box_size = .8;

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
	float box(vec3 p) {
		vec3 q = abs(p) - vec3(box_size);
		return length(max(q,0.0)) + min(max(q.x,max(q.y,q.z)),0.0);
	}
	vec4 sdf(vec3 p) {
		p -= u_center_position;

		return vec4(1., .6, .6, max(julia(5, p * 1.5) / 1.5, box(p)));
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
		p = dir * l + origin;
		for(int i = 0; i < 80; i++) {
			h = sdf(p);
			if(h.w < epsilon) break;
			l += h.w;
			p = dir * l + origin;
			{
				vec3 p2 = abs(p - u_center_position);
				if(max(p2.x, max(p2.y, p2.z)) > box_size) return Hit(l, false, vec3(0), vec3(0));
			}
		}
		return Hit(l, true, h.rgb, p);
	}

	layout(depth_greater) out float gl_FragDepth;
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
		o_metallic_roughness = vec3(.1, .9, 0);
		o_emissive = vec3(0);
	}
GLSL);

//TODO support both sampler2D and sampler2DMS
FRAG_SSAO :: #run incl(UBO_SCREEN_METRICS, gen_kernel(), UBO_CAMERA_PROPERTIES, UBO_TIME_INFO, #string GLSL
	layout(binding = 4) uniform sampler2D u_noise;

	uniform vec2 u_ssao_quality;

	in vec2 vo_uv;
	out vec4 o_color;

	float linearize_depth(float depth) {
		float z = depth * 2 - 1; 
		return (2 * u_near * u_far) / (u_far + u_near - z * (u_far - u_near));	
	}
	vec4 texture_s0(sampler2DMS source, vec2 uv) {
		return texelFetch(source, ivec2(uv * u_window_size), 0);
	}

	void main() {
		vec2 noise_scale = u_ssao_quality / 4; 
		vec2 uv = vo_uv;

		float depth = texture_s0(u_depth, uv).x;
		if(depth >= 1.) {
			o_color = vec4(1);
			return;
		}

		vec3 frag_pos = texture_s0(u_position, uv).xyz;
		vec3 normal = texture_s0(u_normal, uv).xyz;
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

			float scene_depth = texture_s0(u_depth, P.xy).x;
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
	return builder_to_string(*builder,, allocator = temp);
}

VERT_TO_CUBEMAP :: #string GLSL
	uniform uint u_part_id;

	out vec3 vo_direction; 
	void main() {
		vec3 forwards[6] = vec3[6](
			vec3(1, 0, 0), vec3(-1, 0, 0), vec3(0, 1, 0), 
			vec3(0,-1, 0), vec3( 0, 0, 1), vec3(0, 0,-1)
		);
		vec3 ups[6] = vec3[6](
			vec3(0,-1, 0), vec3(0,-1, 0), vec3(0, 0, 1),
			vec3(0, 0,-1), vec3(0,-1, 0), vec3(0,-1, 0)
		);

		float uvs[12] = float[12](0, 0, 1, 1, 0, 1, 0, 0, 1, 0, 1, 1);
		vec2 uv = vec2(uvs[gl_VertexID << 1], uvs[(gl_VertexID << 1) | 1]);
		uv = vec2(uv.x, 1 - uv.y);
		gl_Position = vec4(uv * 2 - 1, 0, 1);

		vec3 forward = forwards[u_part_id];
		vec3 up = ups[u_part_id];
		vec3 right = cross(forward, up);

		vo_direction = forward + up * (uv.y * 2 - 1) + right * (uv.x * 2 - 1);
	}
GLSL
FRAG_PREFILTER :: #string GLSL
	layout(binding = 0) uniform samplerCube u_environment_map;
	uniform float u_roughness;
	// const float u_roughness = .1;
	const float PI = 3.14159265359;

	float RadicalInverse_VdC(uint bits)  {
		bits = (bits << 16u) | (bits >> 16u);
		bits = ((bits & 0x55555555u) << 1u) | ((bits & 0xAAAAAAAAu) >> 1u);
		bits = ((bits & 0x33333333u) << 2u) | ((bits & 0xCCCCCCCCu) >> 2u);
		bits = ((bits & 0x0F0F0F0Fu) << 4u) | ((bits & 0xF0F0F0F0u) >> 4u);
		bits = ((bits & 0x00FF00FFu) << 8u) | ((bits & 0xFF00FF00u) >> 8u);
		return float(bits) * 2.3283064365386963e-10;
	}
	vec2 Hammersley(uint i, uint N) {
		return vec2(float(i)/float(N), RadicalInverse_VdC(i));
	}
	vec3 ImportanceSampleGGX(vec2 Xi, vec3 N, float roughness) {
		float a = roughness*roughness;

		float phi = 2.0 * PI * Xi.x;
		float cosTheta = sqrt((1.0 - Xi.y) / (1.0 + (a*a - 1.0) * Xi.y));
		float sinTheta = sqrt(1.0 - cosTheta*cosTheta);

		vec3 H;
		H.x = cos(phi) * sinTheta;
		H.y = sin(phi) * sinTheta;
		H.z = cosTheta;

		vec3 up        = abs(N.z) < 0.999 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
		vec3 tangent   = normalize(cross(up, N));
		vec3 bitangent = cross(N, tangent);

		vec3 sampleVec = tangent * H.x + bitangent * H.y + N * H.z;
		return normalize(sampleVec);
	}

	in vec3 vo_direction;
	out vec3 o_color;

	void main() {
		vec3 N = normalize(vo_direction);
		vec3 R = N;
		vec3 V = R;

		const uint SAMPLE_COUNT = 1024;
		vec3 prefiltered_color = vec3(0);
		float total_weight = 0;
		for(uint i = 0; i < SAMPLE_COUNT; i++) {
			vec2 Xi = Hammersley(i, SAMPLE_COUNT);
			vec3 H = ImportanceSampleGGX(Xi, N, u_roughness);
			vec3 L = normalize(2 * dot(V, H) * H - V);

			float NdotL = max(dot(N, L), 0);
			if(NdotL > 0) {
				prefiltered_color += texture(u_environment_map, L).rgb * NdotL;
				total_weight += NdotL;
			}
		}
		prefiltered_color /= total_weight;

		o_color = prefiltered_color;
	}
GLSL

SRC_SHADING_MODEL_REFLECTIVE_TEXTURED_V0 :: #string GLSL
	const float PI = 3.141592;
	const float epsilon = 0.00001;
	const vec3 Fdielectric = vec3(0.04);
	#define LOD_MAX_LEVEL 5
	const float gamma = 2.2;

	float ndfGGX(float cosLh, float roughness) {
		float alpha   = roughness * roughness;
		float alphaSq = alpha * alpha;

		float denom = (cosLh * cosLh) * (alphaSq - 1.0) + 1.0;
		return alphaSq / (PI * denom * denom);
	}
	float gaSchlickG1(float cosTheta, float k) {
		return cosTheta / (cosTheta * (1.0 - k) + k);
	}
	float gaSchlickGGX(float cosLi, float cosLo, float roughness) {
		float r = roughness + 1.0;
		float k = (r * r) / 8.0; // Epic suggests using this roughness remapping for analytic lights.
		return gaSchlickG1(cosLi, k) * gaSchlickG1(cosLo, k);
	}
	vec3 fresnelSchlick(vec3 F0, float cosTheta) {
		return F0 + (vec3(1.0) - F0) * pow(1.0 - cosTheta, 5.0);
	}

	vec3 get_color(
		vec3 position, vec3 normal,
		vec3 base_color, vec2 metallic_rouhness, vec3 emissive,
		sampler2D u_brdf, samplerCube u_skybox,
		float ambient_occlusion = 1
	) {
		vec3 albedo = base_color;
		float metallic = metallic_rouhness.x;
		float roughness = metallic_rouhness.y;

		vec3 Lo = normalize(u_eye - position);
		vec3 N = normal;
		
		float cosLo = max(0.0, dot(N, Lo));
		vec3 Lr = 2.0 * cosLo * N - Lo;

		vec3 F0 = mix(Fdielectric, albedo, metallic);

		vec3 directLighting = vec3(0);
		for(int i=0; i<1; ++i)
		{
			// vec3 Li = -lights[i].direction;
			// vec3 Lradiance = lights[i].radiance;
			float phi = u_time * .5;
			vec3 Li = normalize(vec3(1, 1, 1));
			// vec3 Li = normalize(vec3(sin(phi), .1, cos(phi)));
			vec3 Lradiance = vec3(1., .9, .8);

			vec3 Lh = normalize(Li + Lo);

			float cosLi = max(0.0, dot(N, Li));
			float cosLh = max(0.0, dot(N, Lh));

			vec3 F  = fresnelSchlick(F0, max(0.0, dot(Lh, Lo)));
			float D = ndfGGX(cosLh, roughness);
			float G = gaSchlickGGX(cosLi, cosLo, roughness);

			vec3 kd = mix(vec3(1.0) - F, vec3(0.0), metallic);
			vec3 diffuseBRDF = kd * albedo;
			vec3 specularBRDF = (F * D * G) / max(epsilon, 4.0 * cosLi * cosLo);
			directLighting += (diffuseBRDF + specularBRDF) * Lradiance * cosLi;
		}

		vec3 ambientLighting;
		{
			vec3 irradiance = textureLod(u_skybox, N, LOD_MAX_LEVEL).rgb;
			vec3 F = fresnelSchlick(F0, cosLo);
			vec3 kd = mix(vec3(1.0) - F, vec3(0.0), metallic);
			vec3 diffuseIBL = kd * albedo * irradiance;
			vec3 specularIrradiance = textureLod(u_skybox, Lr, roughness * LOD_MAX_LEVEL).rgb;
			vec2 specularBRDF = texture(u_brdf, vec2(cosLo, roughness)).rg;
			vec3 specularIBL = (F0 * specularBRDF.x + specularBRDF.y) * specularIrradiance;
			ambientLighting = diffuseIBL + specularIBL;
		}
		return directLighting + ambientLighting * ambient_occlusion + emissive;
	}
GLSL;
FRAG_LIGHT_PASS :: #run incl(UBO_TIME_INFO, UBO_SCREEN_METRICS, UBO_CAMERA_PROPERTIES, SRC_SHADING_MODEL_REFLECTIVE_TEXTURED_V0, #string GLSL
	layout(binding = 6) uniform sampler2D u_brdf;
	layout(binding = 7) uniform samplerCube u_skybox;
	layout(binding = 8) uniform sampler2D u_ambient_occlusion;

	in vec2 vo_uv;
	out vec4 o_color;

	vec3 color_by_sampler_id(vec2 uv, int sample_id) {
		ivec2 uvs = ivec2(uv * u_window_size);

		vec3 base_color = texelFetch(u_color, uvs, sample_id).xyz;
		// if(fract(u_time * .5) < .5) {
		// 	base_color = source_color_cor_correction(base_color);
		// }

		float depth = texelFetch(u_depth, uvs, sample_id).x;
		if(depth >= 1) {
			return base_color;
		} else {
			vec3 normal = texelFetch(u_normal, uvs, sample_id).xyz;
			vec3 position = texelFetch(u_position, uvs, sample_id).xyz;
			vec3 emissive = texelFetch(u_emissive, uvs, sample_id).xyz;
			vec2 mr = texelFetch(u_metallic_roughness, uvs, sample_id).yx;
			float 
			ao = texture(u_ambient_occlusion, uv).x;
			// if(fract(u_time * .5) < .5) 
			// ao = 1;
			return get_color(
				position, normal, 
				base_color, mr, emissive,
				u_brdf, u_skybox,
				ao
			);
		}
	}

	// vec3 color_no_sampling(vec2 uv) {
	// 	vec3 base_color = texture(u_color, uv).xyz;

	// 	float depth = texture(u_depth, uv).x;
	// 	if(depth >= 1) {
	// 		return base_color;
	// 	} else {
	// 		vec3 normal = texture(u_normal, uv).xyz;
	// 		vec3 position = texture(u_position, uv).xyz;
	// 		vec3 emissive = texture(u_emissive, uv).xyz;
	// 		vec2 mr = texture(u_metallic_roughness, uv).yx;
	// 		float 
	// 		ao = texture(u_ambient_occlusion, uv).x;
	// 		// if(fract(u_time * .5) < .5) 
	// 		// ao = 1;
	// 		return get_color(
	// 			position, normal, 
	// 			base_color, mr, emissive,
	// 			u_brdf, u_skybox,
	// 			ao
	// 		);
	// 	}
	// }
	void main() {
		// vec3 color = color_no_sampling(vo_uv);

		vec3 color = vec3(0);
		int samples = 4;
		for(int i = 0; i < samples; i++) {
			color += color_by_sampler_id(vo_uv, i);
		}
		color /= samples;

		o_color = vec4(color, 1);
	}
GLSL);

FRAG_BLUR :: #run incl(UBO_SCREEN_METRICS, UBO_TIME_INFO, #string GLSL
	in vec2 vo_uv;
	out vec4 o_color;

	uniform vec2 u_ssao_quality;

	vec4 texture_s0(sampler2DMS source, vec2 uv) {
		return texelFetch(source, ivec2(uv * u_window_size), 0);
	}

	void main() {
		vec2 uv = vo_uv;
		vec2 texture_factor = 1.0 / u_ssao_quality;

		float kernel[4] = float[4](1, 1, 1, 1);
		const float S = 1. / (4 * 4);

		float occlusion = 0;
		float depth = texture_s0(u_depth_0, uv).x;
		// float depth = texture(u_depth_0, uv).x;
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
		o_color = vec4(vec3(occlusion), 1);
	}
GLSL);

FRAG_BACKGROUND_CUBEMAP :: #string GLSL
	layout(binding = 0) uniform samplerCube skybox;
	in vec3 vo_direction;
	void main() {
		vec4 base_color = texture(skybox, vo_direction);
		#ifdef O_COLOR
			o_color = base_color.xyz;
		#else
			#ifdef O_COLOR4
				o_color = base_color;
			#endif
		#endif
		#ifdef O_NORMAL
			o_normal = -normalize(vo_direction);
		#endif
		#ifdef O_POSITION
			o_position = vec3(vo_direction * 100000);
		#endif
		#ifdef O_METALLIC_ROUGHNESS
			o_metallic_roughness = vec3(0);
		#endif
		#ifdef O_EMISSIVE
			o_emissive = vec3(0);
		#endif
	}
GLSL

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
VERT_SCREEN_CUBE :: #run incl(UBO_CAMERA_PROPERTIES, #string GLSL
	out vec3 vo_direction;
	void main() {
		vec3 points[8] = vec3[8](
			vec3( 1, -1, -1), vec3( 1, -1,  1),
			vec3(-1, -1,  1), vec3(-1, -1, -1),
			vec3( 1,  1, -1), vec3( 1,  1,  1),
			vec3(-1,  1,  1), vec3(-1,  1, -1)
		);
		int indices[36] = int[36](
			1, 2, 3, 7, 6, 5, 4, 5, 1, 5, 6, 2,
			2, 6, 7, 0, 3, 7, 0, 1, 3, 4, 7, 5,
			0, 4, 1, 1, 5, 2, 3, 2, 7, 4, 0, 7
		);
		vec3 p = points[indices[gl_VertexID]];
		vo_direction = p;
		gl_Position = u_mat_p * u_mat_r * vec4(p, 1);
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
