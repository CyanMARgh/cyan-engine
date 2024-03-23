#import,dir "../core";
#import "Basic"()(MEMORY_DEBUGGER = true);
#import "Math";
#import "GL";
#import "Random";

cursor_world_position :: () -> Vector2 {
	position := backend_state.cursor_position;
	return .{
		backend_state.window_metrics.width * (2 * position.x / backend_state.window_metrics.width - 1) / backend_state.window_metrics.height, 
		1 - 2 * position.y / backend_state.window_metrics.height
	};
}

main :: () {
	defer report_memory_leaks();
	init_resources(); defer deinit_resources();
	init_default_graphics(); defer deinit_default_graphics();

	shader_particles := compile_shader_vf(VERT_PARTICLE, FRAG_PARTICLE);
	defer deinit(*shader_particles);

	particle_system : Particle_System;
	init(*particle_system); defer deinit(*particle_system);

	glEnable(GL_BLEND);
	glBlendFunc(GL_SRC_ALPHA, GL_ONE);
	for window_cycle(fps_log_period = 200) {
		for Events {
			if it.type == {
				case .KEY; using it.key_event;
				if type == .PRESS ifx keycode == {
					case GLFW_KEY_ESCAPE; exit();
					case #char"P"; screenshot();
				}
				case .MOUSE_BUTTON; using it.mouse_button_event;
			}
		}
		update_default_camera();
		if backend_state.mouse_buttons_down[0] {
			emit(*particle_system, 100, cursor_world_position());
		}
		simulate(*particle_system, delta_time);

		glClearColor(0, 0, 0, 1);
		glClear(GL_COLOR_BUFFER_BIT | GL_STENCIL_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

		use(*shader_particles);
		draw(particle_system);
	}
}

Particle :: struct {
	time : float;
	position : Vector2;
	velocity : Vector2;
}
Particle_System :: struct {
	#as using painter : Atoms_Painter(Particle);
}
init :: (particle_system : *Particle_System) {
	particle_system.painter = make_atoms_painter(Particle, 100000);
}
simulate :: (using particle_system : *Particle_System, dt : float) {
	for * buffer {
		using it;
		time -= dt;
		if time < 0 {
			remove it;
		} else {
			position += velocity * dt;
			velocity += Vector2.{0, 2} * dt;
			velocity *= 1 - dt * 3;
		}
	}
	commit_buffer(particle_system);
}
emit :: (using particle_system : *Particle_System, count := 100, center := Vector2.{}) {
	for i : 1..count {
		direction := Vector2.{random_get_within_range(-1, 1), random_get_within_range(-1, 1)};
		direction /= length(direction);
		direction *= random_get_within_range(.3, .7);
		array_add(*buffer, .{
			random_get_within_range(.5, 1.5), 
			center,
			direction
		});
	}
}

VERT_PARTICLE :: #run incl(UBO_SCREEN_METRICS, #string GLSL
	layout (location = 0) in float a_time;
	layout (location = 1) in vec2 a_position;
	layout (location = 2) in float a_velocity;

	out vec2 vo_uv;
	void main() {
		float points[12] = float[12](0, 0, 1, 1, 0, 1, 0, 0, 1, 0, 1, 1);
		vec2 p = vec2(points[gl_VertexID << 1], points[(gl_VertexID << 1) | 1]);
		float size = (1 - 1 / (1 + a_time)) * 0.05; 
		vec2 uv = p * 2 - 1;
		vo_uv = uv;
		gl_Position = vec4((a_position + uv * size) * vec2(1. / u_width_over_height, 1.), 0, 1);
	}
GLSL);
FRAG_PARTICLE :: #string GLSL
	in vec2 vo_uv;
	out vec4 o_color;	
	void main() {
		o_color = vec4(vec3(1.5, .5, .2), (1 - length(vo_uv)) * .5 );
	}
GLSL
