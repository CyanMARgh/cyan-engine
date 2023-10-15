UBO_SCREEN_METRICS :: #string GLSL
	layout(std140, binding = 0) uniform ubo_screen_metrics {
		ivec2 u_window_size;
		float u_width_over_height;
		float u_height_over_width;
	};
GLSL
UBO_CAMERA_PROPERTIES :: #string GLSL
	layout(std140, binding = 1) uniform ubo_camera_properties {		
		mat4 u_mat_t, u_mat_r, u_mat_p;
		mat4 u_mat_trp;

		float u_near, u_far;
		vec3 u_eye;
	};
GLSL
UBO_MAT_M :: #string GLSL
	layout(std140, binding = 2) uniform ubo_mat_m {
		mat4 u_mat_m;
	};
GLSL
UBO_TIME_INFO :: #string GLSL
	layout(std140, binding = 3) uniform ubo_time_info {
		float u_time;
		float u_delta_time;
	};
GLSL
UBO_MATERIAL :: #string GLSL
	const int BASE_COLOR 			= 0x1;
	const int METALLIC_ROUGHNESS 	= 0x2;
	const int NORMAL 				= 0x4;
	const int OCCLUSION 			= 0x8;
	const int EMISSIVE			 	= 0x10;
	const int DOUBLE_SIDED 		 	= 0x20;
	const int TRANSMISSION 		 	= 0x40;

	const int ALPHA_MODE 			= 0x380;
	const int OPAQUE				= 0x080;
	const int MASK				 	= 0x100;
	const int BLEND				 	= 0x200;

	layout(std140, binding = 4) uniform ubo_material {
		int u_flags;

		vec4 u_base_color_factor;
		float u_metallic_factor;
		float u_roughness_factor;
		vec3 u_emissive_factor;
		float u_transmission_factor;

		float u_alpha_cutoff;
		float u_ior;
		float u_emissive_strength;

		float u_normal_scale;
		float u_occlusion_strength;
	};
GLSL

GLTF_TEXTURES :: #string GLSL
	layout(binding = 0) uniform sampler2D u_base_color;
	layout(binding = 1) uniform sampler2D u_metallic_roughness;
	layout(binding = 2) uniform sampler2D u_normal;
	layout(binding = 3) uniform sampler2D u_occlusion;
	layout(binding = 4) uniform sampler2D u_emissive;
	layout(binding = 5) uniform sampler2D u_transmission;	
GLSL

VERTICE_INTERFACE_OUT :: #string GLSL
	struct Input_Vertice {
		vec3 position;
		vec3 normal;
		vec2 uv_0;
	};
	Input_Vertice gen_vertice();
	out struct VO {
		vec3 position;
		vec3 normal;
		vec2 uv_0;
	} vo;
	void main() {
		Input_Vertice input_vertice = gen_vertice();
		vec4 world_pos = u_mat_m * vec4(input_vertice.position, 1);
		gl_Position = u_mat_trp * world_pos;
		vo = VO(
			world_pos.xyz,
			normalize((vec4(input_vertice.normal, 0) * inverse(u_mat_m)).xyz),
			input_vertice.uv_0
		);
	}
GLSL
DSTHEADER_DEFAULT :: #string GLSL
	#define O_COLOR4
	layout(location = 0) out vec4 o_color;
GLSL

SRC_FRAG_EXTENDED :: #run incl(UBO_MATERIAL, UBO_CAMERA_PROPERTIES, GLTF_TEXTURES, #string GLSL
	in struct VO {
		vec3 position;
		vec3 normal;
		vec2 uv_0;
	} vo;

	void main() {
		vec2 uv_0 = vo.uv_0;

		vec4 base_color = u_base_color_factor;
		if((u_flags & BASE_COLOR) != 0) {
			base_color *= texture(u_base_color, uv_0);
		}
		#ifdef O_COLOR
			o_color = base_color.xyz;
		#else
			#ifdef O_COLOR4
				o_color = base_color;
			#endif
		#endif
		#ifdef O_NORMAL
			vec3 normal = normalize(vo.normal);
			if(!gl_FrontFacing) normal *= -1;
			o_normal = normal;
		#endif
		#ifdef O_POSITION
			o_position = vo.position;
		#endif
		#ifdef O_METALLIC_ROUGHNESS
			vec2 metallic_roughness;
			if((u_flags & METALLIC_ROUGHNESS) != 0) {
				metallic_roughness = texture(u_metallic_roughness, uv_0).yz;
			} else {
				metallic_roughness = vec2(u_metallic_factor, u_roughness_factor);
			}
			o_metallic_roughness = vec3(metallic_roughness.xy, 0);
		#endif
		#ifdef O_EMISSIVE
			vec3 emissive = u_emissive_strength * u_emissive_factor;
			if((u_flags & EMISSIVE) != 0) {
				emissive = texture(u_emissive, uv_0).xyz;
			}
			o_emissive = emissive;
		#endif
	}
GLSL);

SRC_TARGET_MAIN :: #string GLSL
	#define O_COLOR4
	layout(location = 0) out vec4 o_color;
GLSL


