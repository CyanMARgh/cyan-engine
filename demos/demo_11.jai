#import,dir "../core";
#import "Basic"()(MEMORY_DEBUGGER = true);
#import "Math";
#import "GL";

main :: () {
	defer report_memory_leaks();
	init_resources(); defer deinit_resources();
	init_default_graphics(); defer deinit_default_graphics();

	shader_show_texture := compile_shader_vf(VERT_SCREEN_QUAD, FRAG_SHOW_TEXTURE);
	defer deinit(*shader_show_texture);
	shader_show_cubemap := compile_shader_vf(VERT_SCREEN_CUBE, FRAG_SHOW_CUBEMAP);
	defer deinit(*shader_show_cubemap);
	shader_sphere := compile_shader_vf(VERT_SPHERE, FRAG_REFLECTIVE);
	defer deinit(*shader_sphere);

	source_cubemap, ok := load_cubemap_from_file("res/yokohama2/", "posx.jpg", "negx.jpg", "posy.jpg", "negy.jpg", "posz.jpg", "negz.jpg");
	assert(ok);
	defer deinit(*source_cubemap);

	BRDF_RESOLUTION :: 128;
	texture_brdf := make_texture_buffer(BRDF_RESOLUTION, BRDF_RESOLUTION, .{GL_RGB, GL_RGB, GL_UNSIGNED_BYTE, 0, GL_TEXTURE_2D});
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

	glEnable(GL_CULL_FACE);
	for window_cycle(capture_video = false) {
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

		bind_default_target();
			// for *shader_show_texture {
			// 	bind_sampler(0, texture_brdf);
			// 	draw_empty_mesh(6);
			// }

			shown_cubemap := prerendered_cubemap;
			glClearColor(.7, .8, .9, 1);
			glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

			glDisable(GL_DEPTH_TEST);
			glCullFace(GL_FRONT);
				use(*shader_show_cubemap);
					bind_sampler(0, source_cubemap);
					draw_empty_mesh(36);
			glCullFace(GL_BACK);
			glEnable(GL_DEPTH_TEST);

			use(*shader_sphere);
				rows, columns : u32 = 20, 30;
				set(*shader_sphere, "u_columns", columns);
				set(*shader_sphere, "u_rows", rows);
				bind_sampler(0, shown_cubemap);
				bind_sampler(1, texture_brdf);

				for j : 0..7 {
					for i : 0..7 {
						// default_material.metallic_factor = i * .1;
						// default_material.roughness_factor = j * .1;
						// refresh_on_gpu(*default_material);
						set(*shader_sphere, "u_metallic", cast(float)(i / 7.));
						set(*shader_sphere, "u_roughness", cast(float)(j / 7.));

						set_model_transform(make_translation_matrix4(.{(j - 5) * 1.2, (i - 5) * 1.2, -9}) * make_scale_matrix4(.{.5, .5, .5}));
						draw_empty_mesh(rows * columns * 6);
					}
				}
				// set_model_transform(make_scale_matrix4(.{1, 1, 1}));
				// draw_empty_mesh(rows * columns * 6);

		check_gl_error();
	}
}

FRAG_SHOW_TEXTURE :: #run incl(UBO_CAMERA_PROPERTIES, #string GLSL
	layout(binding = 0) uniform sampler2D u_color;
	in vec2 vo_uv;
	out vec4 o_color;
	void main() {
		o_color = texture(u_color, vo_uv);
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
FRAG_SHOW_CUBEMAP :: #run incl(UBO_TIME_INFO, #string GLSL
	layout(binding = 0) uniform samplerCube skybox;
	in vec3 vo_direction;
	out vec4 o_color;
	void main() {
		// o_color = textureLod(skybox, normalize(vo_direction), (sin(u_time) * .5 + .5) * 5);
		// o_color = textureLod(skybox, normalize(vo_direction), 0);
		o_color = texture(skybox, vo_direction);

		// vec3 color = normalize(vo_direction) * .5 + .5;
		// ivec3 P = ivec3(floor(vo_direction * 9.9));
		// if(mod(P.x + P.y + P.z, 2) == 0) {
		// 	color *= .3;
		// }
		// o_color = vec4(color, 1);
	}
GLSL);
FRAG_REFLECTIVE :: #run incl(UBO_CAMERA_PROPERTIES, UBO_TIME_INFO, #string GLSL
	layout(binding = 0) uniform samplerCube u_skybox;
	layout(binding = 1) uniform sampler2D u_brdf;

	const float PI = 3.14159265359;
	const float RECIPROCAL_PI = 0.318309886;
	uniform float u_roughness;

	in struct VO {
		vec3 position;
		vec3 normal;
		vec2 uv_0;
	} vo;
	out vec4 o_color;

	void main() {
		vec3 V = normalize(u_eye - vo.position);
		vec3 N = normalize(vo.normal);
		vec3 SpecularColor = vec3(1);
		float roughness = u_roughness;

		float NoV = clamp(dot(N, V), 0, 1);
		vec3 R = 2 * dot(V, N) * N - V;
		vec3 PrefilteredColor = textureLod(u_skybox, R, roughness * 5).xyz;
		vec2 EnvBRDF = texture(u_brdf, vec2(NoV, roughness)).xy;
		vec3 result_color = 
			PrefilteredColor * 
			(SpecularColor * EnvBRDF.x + EnvBRDF.y);

		o_color = vec4(result_color, 1);
	}
GLSL);


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
FRAG_SHOW_UV :: #string GLSL
	layout(binding = 0) uniform samplerCube u_environment_map;
	in vec3 vo_direction;
	out vec3 o_color;

	void main() {
		o_color = texture(u_environment_map, normalize(vo_direction)).xyz;
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
FRAG_BRDF :: #string GLSL
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
	vec3 ImportanceSampleGGX(vec2 Xi, vec3 N, float Roughness) {
		float a = Roughness * Roughness;
		float Phi = 2 * PI * Xi.x;
		float CosTheta = sqrt((1 - Xi.y) / (1 + (a * a - 1) * Xi.y));
		float SinTheta = sqrt(1 - CosTheta * CosTheta);
		vec3 H;
		H.x = SinTheta * cos(Phi);
		H.y = SinTheta * sin(Phi);
		H.z = CosTheta;
		vec3 UpVector = abs(N.z) < 0.999 ? vec3(0,0,1) : vec3(1,0,0);
		vec3 TangentX = normalize(cross(UpVector, N));
		vec3 TangentY = cross(N, TangentX);

		return TangentX * H.x + TangentY * H.y + N * H.z;
	}
	float GeometrySchlickGGX(float NdotV, float roughness) {
		float a = roughness;
		float k = (a * a) / 2.0;

		float nom   = NdotV;
		float denom = NdotV * (1.0 - k) + k;

		return nom / denom;
	}
	float GeometrySmith(vec3 N, vec3 V, vec3 L, float roughness) {
		float NdotV = max(dot(N, V), 0.0);
		float NdotL = max(dot(N, L), 0.0);
		float ggx2 = GeometrySchlickGGX(NdotV, roughness);
		float ggx1 = GeometrySchlickGGX(NdotL, roughness);

		return ggx1 * ggx2;
	}
	vec2 IntegrateBRDF(float NdotV, float roughness) {
		vec3 V;
		V.x = sqrt(1.0 - NdotV * NdotV);
		V.y = 0.0;
		V.z = NdotV;

		float A = 0.0;
		float B = 0.0;

		vec3 N = vec3(0.0, 0.0, 1.0);

		const uint SAMPLE_COUNT = 1024u;
		for(uint i = 0u; i < SAMPLE_COUNT; ++i) {
			vec2 Xi = Hammersley(i, SAMPLE_COUNT);
			vec3 H  = ImportanceSampleGGX(Xi, N, roughness);
			vec3 L  = normalize(2.0 * dot(V, H) * H - V);

			float NdotL = max(L.z, 0.0);
			float NdotH = max(H.z, 0.0);
			float VdotH = max(dot(V, H), 0.0);

			if(NdotL > 0.0) {
				float G = GeometrySmith(N, V, L, roughness);
				float G_Vis = (G * VdotH) / (NdotH * NdotV);
				float Fc = pow(1.0 - VdotH, 5.0);

				A += (1.0 - Fc) * G_Vis;
				B += Fc * G_Vis;
			}
		}
		return vec2(A, B) / float(SAMPLE_COUNT);
	}

	in vec2 vo_uv;
	out vec3 o_color;

	void main() {
		o_color = vec3(IntegrateBRDF(vo_uv.x, vo_uv.y), 0); 
	}
GLSL
