#import,dir "../core";
#import "Basic"()(MEMORY_DEBUGGER = true);
#import "GL";
 
main :: () {
	defer report_memory_leaks();
	init_resources(); defer deinit_resources();
	init_default_graphics(); defer deinit_default_graphics();

	shader_cube := compile_shader_vf(VERT_CUBE, FRAG_RAYMARCHED_ZONE);
	defer deinit(*shader_cube);

	glEnable(GL_CULL_FACE);
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

		glClearColor(.7, .8, .9, 1);
		glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

		use(*shader_cube);
			draw_empty_mesh(36);
	}
}


FRAG_RAYMARCHED_ZONE :: #run incl(UBO_CAMERA_PROPERTIES, UBO_MAT_M, DSTHEADER_DEFAULT, #string GLSL
	in struct VO {
		vec3 position;
		vec3 normal;
		vec2 uv_0;
	} vo;

	vec4 sdf(vec3 p) {
		p -= u_center_position;
		return vec4(vec3(1, 1, 1), length(p) - 1);
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
	const float box_size = 1.;
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

		#ifdef O_COLOR4
			o_color = vec4(hit.color, 1);
		#else
			#ifdef O_COLOR
				o_color = hit.color;
			#endif
		#endif
	}
GLSL);