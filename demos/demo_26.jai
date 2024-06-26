#import,dir "../core";
#import "Basic"()(MEMORY_DEBUGGER = true);
#import "Math";
#import "GL";

main :: () {
	defer report_memory_leaks();
	init_resources(); defer deinit_resources();
	init_default_graphics(); defer deinit_default_graphics();

	fb_gbuffer := make_framebuffer(1280, 720, 
		.{"depth", .DEPTH, GL_DEPTH_COMPONENT32},
		.{"color", .COLOR, GL_RGB8},
		.{"normal", .COLOR, GL_RGB16F},
		// .{"position", .COLOR, GL_RGB16F}
		.{"index", .COLOR, GL_R16UI}
	);
	defer deinit(*fb_gbuffer);

	Screen_Probe :: struct {
		index : u32;
	}

	ssbo_screen_probe := make_ssbo_new(Screen_Probe);
	defer deinit(*ssbo_screen_probe);

	shader_cube := compile_shader_vf(VERT_CUBE, incl(dstheader(fb_gbuffer), FRAG_EXTENDED));
	defer deinit(*shader_cube);
	shader_screen_pass := compile_shader_vf(VERT_SCREEN_QUAD, incl(/*srcheader(fb_gbuffer),*/ DSTHEADER_DEFAULT, FRAG_SCREEN_SHOW_COLOR));
	defer deinit(*shader_screen_pass);
	shader_probe := compile_shader_c(COMP_PICK_COLOR);
	defer deinit(*shader_probe);

	graphics_state.default_camera = .{.{yaw = 0.727887, pitch = -0.784, position = .{24.633928, 14.278154, 23.129793}, near = 0.1, far = 1000, fow_vertical = 0.942478, screen_size = .{1280, 720} }, 3, 0.15, 0.002, 1.570796};

	glEnable(GL_CULL_FACE);
	check_gl_error();
	for window_cycle() {
		for Events if it.type == {
			case .KEY; using it.key_event;
			if type == .PRESS ifx keycode == {
				case GLFW_KEY_ESCAPE; exit();
				case #char"P"; screenshot();
				case #char"C"; print("camera = %\n", graphics_state.default_camera);
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
				for x : 0..9 for y : 0..9 for translate(.{2.2 * x, 0, 2.2 * y}) {
					set_model_transform(graphics_state.scene_translation);
					for *shader_cube {
						set("u_index_0", cast(s32)(1 + x + y * 10));
						draw_empty_mesh(36);
					}
				}
			glDisable(GL_DEPTH_TEST);

		for *shader_probe {
			bind_as_source(fb_gbuffer);
			bind(0, ssbo_screen_probe);
			compute();
		}

		screen_probe := get_header(ssbo_screen_probe);
		// print("%\n", screen_probe);

		bind_default_target();
			for *shader_screen_pass {
				bind_as_source(fb_gbuffer);
				draw_empty_mesh(6);
			}

		check_gl_error();
	}
}

SSBO_new :: struct(Head : Type, Item : Type, Extra_Align :u32= 1) {
	id : u32;

	max_elements : u32;

	HEAD_ALIGN :: #run min(align_of(Head), align_of(Item), Extra_Align);
	ARRAY_OFFSET :: #run (size_of(Head) + HEAD_ALIGN - 1) / HEAD_ALIGN * HEAD_ALIGN;
}
make_ssbo_new :: ($_Head : Type, $_Item : Type = void, _max_elements :u32= 10000, $_Extra_Align :u32= 1) -> SSBO_new(_Head, _Item, _Extra_Align) {
	using result : SSBO_new(_Head, _Item, _Extra_Align) = .{max_elements = _max_elements};
	glGenBuffers(1, *id);
	glBindBuffer(GL_SHADER_STORAGE_BUFFER, id);
		glBufferData(GL_SHADER_STORAGE_BUFFER, ARRAY_OFFSET + size_of(Item) * max_elements, null, GL_DYNAMIC_COPY);
	glBindBuffer(GL_SHADER_STORAGE_BUFFER, 0);

	return result;
}
refresh :: (using ssbo : *SSBO_new($Head, $Item), head : Head, items : []Item = .[]) {
	assert(items.count <= max_elements);

	glBindBuffer(GL_SHADER_STORAGE_BUFFER, id);
		glBufferData(GL_SHADER_STORAGE_BUFFER, ARRAY_OFFSET + size_of(Item) * items.count, null, GL_DYNAMIC_COPY);
		glBufferSubData(GL_SHADER_STORAGE_BUFFER, 0, size_of(Head), *head);
		if items {
			glBufferSubData(GL_SHADER_STORAGE_BUFFER, ARRAY_OFFSET, items.count * size_of(Item), items.data);
		}
	glBindBuffer(GL_SHADER_STORAGE_BUFFER, 0);
}
get_header :: (using ssbo : SSBO_new($Head, $Item)) -> Head {
	head : Head;
	glGetNamedBufferSubData(id, 0, size_of(Head), *head);
	return head;
}

deinit :: (using ssbo : *SSBO_new) {
	glDeleteBuffers(1, *id);
}

bind :: (slot : u32, using ssbo : SSBO_new) {
	glBindBufferBase(GL_SHADER_STORAGE_BUFFER, slot, id); 
}

COMP_PICK_COLOR :: #run incl(UBO_SCREEN_METRICS, #string GLSL
	layout(binding = 3) uniform usampler2D u_index;

	layout(std430, binding = 0) buffer ssbo_screen_probe {
		uint b_index;
	};

	void main() {
		ivec3 p0 = ivec3(gl_GlobalInvocationID.xyz);
		if(p0.x > 0 || p0.y > 0 || p0.z > 0) return;

		vec2 uv = u_cursor_position / u_window_size;
		uv.y = 1 - uv.y;

		b_index = texture(u_index, uv).x;
	}
GLSL);

FRAG_SCREEN_SHOW_COLOR :: #string GLSL
	#define U_SAMPLER2D_DEPTH
	layout(binding = 0) uniform sampler2D u_depth;
	#define U_SAMPLER2D_COLOR
	layout(binding = 1) uniform sampler2D u_color;
	#define U_SAMPLER2D_NORMAL
	layout(binding = 2) uniform sampler2D u_normal;
	#define U_SAMPLER2D_INDEX
	layout(binding = 3) uniform usampler2D u_index;

	layout(std430, binding = 0) buffer ssbo_screen_probe {
		uint b_index;
	};

	in vec2 vo_uv;

	const float PHI = (1 + sqrt(5)) / 2;
	const float PI = 3.14159265359;

	vec3 hsv2rgb(vec3 c) {
		vec4 K = vec4(1., 2. / 3., 1. / 3., 3.);
		return c.z * mix(K.xxx, clamp(abs(fract(c.x + K.xyz) * 6. - K.w) - K.x, 0, 1), c.y);
	}
	
	void main() {
		vec2 uv = vo_uv;
		vec3 color;

		uint index = texture(u_index, uv).x;
		// color = index == 0 ? vec3(0) : index == b_index ? vec3(1) : hsv2rgb(vec3(float(index) * PHI, 1, 1));

		color = index == 0 ? vec3(0) : index == b_index ? vec3(1) : vec3(.5);

		// if(uv.y > .5) {
		// 	uv.y = uv.y * 2 - 1;
		// 	if(uv.x > .5) {
		// 		uv.x = uv.x * 2 - 1;
		// 		color = texture(u_color, uv).xyz;
		// 	} else {
		// 		uv.x = uv.x * 2;
		// 		color = texture(u_depth, uv).xxx;
		// 	}
		// } else {
		// 	uv.y = uv.y * 2;
		// 	if(uv.x > .5) {
		// 		uv.x = uv.x * 2 - 1;
		// 		color = texture(u_normal, uv).xyz;
		// 	} else {
		// 		uv.x = uv.x * 2;
		// 		uint index = texture(u_index, uv).x;
		// 		color = index != 0 ? hsv2rgb(vec3(float(index) * PHI, 1, 1)) : vec3(0);
		// 		// color = texture(u_position, uv).xyz;
		// 	}
		// }
		o_color = vec4(color, 1);
	}
GLSL