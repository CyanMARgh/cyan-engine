#import,dir "../core";
#import "Basic"()(MEMORY_DEBUGGER = true);
#import "Math";
#import "GL";
#import "Random";

coordinate_screen_to_world :: (position : Vector2) -> Vector3 {
	using backend_state.window_metrics;
	return .{
		width * (2 * position.x / width - 1) / height, 
		1 - 2 * position.y / height,
		0
	};
}
cursor_world_position :: () -> Vector3 {
	return coordinate_screen_to_world(backend_state.cursor_position);
}

USE_SHADER_FIRE :: true;

main :: () {
	defer report_memory_leaks();
	init_resources(); defer deinit_resources();
	init_default_graphics(); defer deinit_default_graphics();

	#if USE_SHADER_FIRE {
		shader_particles := compile_shader_vf(VERT_PARTICLE, FRAG_PARTICLE_FIRE);
	} else {
		shader_particles := compile_shader_vf(VERT_PARTICLE, FRAG_PARTICLE_CHECKERS);
	}

	defer deinit(*shader_particles);

	particle_system : Particle_System;
	init(*particle_system); defer deinit(*particle_system);

	#if USE_SHADER_FIRE {
		glEnable(GL_BLEND);
		glBlendFunc(GL_SRC_ALPHA, GL_ONE);
	} else {
		glEnable(GL_BLEND);
		glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
	}

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
			pos_new := coordinate_screen_to_world(backend_state.cursor_position);
			pos_old := coordinate_screen_to_world(backend_state.cursor_position - backend_state.cursor_delta);

			emit(*particle_system, 80, pos_old, pos_new);
		}
		simulate(*particle_system, delta_time);

		glClearColor(0, 0, 0, 1);
		glClear(GL_COLOR_BUFFER_BIT | GL_STENCIL_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

		use(*shader_particles);
		draw(particle_system);
	}
}

Particle_CPU_Part :: struct {
	velocity : Vector3;
}
Particle_GPU_Part :: struct {
	position : Vector3;
	time : float;
	base_color : Vector3;
	aspect_color : Vector3;
}

Particle_System :: struct {
	vao, instance_vbo : u32;
	max_particles : u32;
	buffer_cpu	: [..]Particle_CPU_Part;
	buffer_gpu	: [..]Particle_GPU_Part;
}
init :: (using particle_system : *Particle_System, _max_particles :u32= 100000) {
	add_attrib :: (size : int) #expand {
		glEnableVertexAttribArray(xx attr_index);
		glVertexAttribPointer(xx attr_index, size, GL_FLOAT, GL_FALSE, size_of(Particle_GPU_Part), xx offset); // position
		glVertexAttribDivisor(xx attr_index, 1);
		offset += size * 4;
		attr_index += 1;
	}

	max_particles = _max_particles;
	glGenVertexArrays(1, *vao);
	glGenBuffers(1, *instance_vbo);

	glBindVertexArray(vao);
		glBindBuffer(GL_ARRAY_BUFFER, instance_vbo);
		glBufferData(GL_ARRAY_BUFFER, size_of(Particle_GPU_Part) * max_particles, null, GL_STATIC_DRAW);
		offset := 0;
		attr_index := 0;
		add_attrib(3);
		add_attrib(1);
		add_attrib(3);
		add_attrib(3);
	// glBindBuffer(GL_ARRAY_BUFFER, 0);
	glBindVertexArray(0);
}
deinit :: (using particle_system : *Particle_System) {
	glDeleteVertexArrays(1, *vao);
	glDeleteBuffers(1, *instance_vbo);
	array_reset(*buffer_cpu);
	array_reset(*buffer_gpu);
}

commit_buffer :: (using particle_system : *Particle_System) {
	glBindBuffer(GL_ARRAY_BUFFER, instance_vbo);
	// print("%\n", buffer_gpu);
	glBufferSubData(GL_ARRAY_BUFFER, 0, size_of(Particle_GPU_Part) * buffer_gpu.count, buffer_gpu.data);	
	glBindBuffer(GL_ARRAY_BUFFER, 0);
}
draw :: (using particle_system : Particle_System) {
	glBindVertexArray(vao);
	// print("count = % / %\n", buffer_gpu.count, buffer_cpu.count);
	glDrawArraysInstanced(GL_TRIANGLES, 0, 6, xx buffer_gpu.count);
}
simulate :: (using particle_system : *Particle_System, dt : float) {
	i := 0;
	while i < buffer_cpu.count {
		buffer_gpu[i].time -= dt;
		if buffer_gpu[i].time < 0 {
			count := buffer_cpu.count - 1;
			buffer_cpu[i] = buffer_cpu[count]; buffer_cpu.count = count;
			buffer_gpu[i] = buffer_gpu[count]; buffer_gpu.count = count;
		} else {
			buffer_gpu[i].position += buffer_cpu[i].velocity * dt;
			buffer_cpu[i].velocity += Vector3.{0, 2, 0} * dt;
			buffer_cpu[i].velocity *= 1 - dt * 3;
			i += 1;
		}
	}
	commit_buffer(particle_system);
}
emit :: (using particle_system : *Particle_System, count := 100, center : Vector3) {
	emit(particle_system, count, center, center);
}
emit :: (using particle_system : *Particle_System, count : int, center_0 : Vector3, center_1 : Vector3) {
	to_emit := min(count, max_particles - buffer_cpu.count);
	for i : 0..to_emit-1 {
		center := center_0 + (center_1 - center_0) * (cast(float)i / (to_emit-1));
		direction := Vector3.{random_get_within_range(-1, 1), random_get_within_range(-1, 1), random_get_within_range(-1, 1)};
		direction /= length(direction);
		P0 := array_add(*buffer_cpu);
		P1 := array_add(*buffer_gpu);

		P0.velocity = direction * random_get_within_range(.3, .7);

		P1.time = random_get_within_range(.5, 1.5);
		P1.position = .{center.x, center.y, 0.};
		// P1.base_color = .{1.5, .5, .2};
		P1.base_color = .{.5, .2, 1.5};
		P1.aspect_color = .{1., 1., 1.};
	}
}

VERT_PARTICLE :: #run incl(UBO_SCREEN_METRICS, #string GLSL
	layout (location = 0) in vec3 a_position;
	layout (location = 1) in float a_time;
	layout (location = 2) in vec3 a_base_color;
	layout (location = 3) in vec3 a_aspect_color;

	out struct VO {
		vec2 uv;
		vec3 base_color;
		vec3 aspect_color;
	} vo;

	void main() {
		float points[12] = float[12](0, 0, 1, 1, 0, 1, 0, 0, 1, 0, 1, 1);
		vec2 p = vec2(points[gl_VertexID << 1], points[(gl_VertexID << 1) | 1]);
		float size = (1 - 1 / (1 + a_time * 1)) * 0.05; 
		vec2 uv = p * 2 - 1;
		vo.uv = uv;
		vo.aspect_color = a_aspect_color;
		vo.base_color = a_base_color;
		gl_Position = vec4((a_position.xy + uv * size) * vec2(1. / u_width_over_height, 1.), 0, 1);
	}
GLSL);
FRAG_PARTICLE_FIRE :: #string GLSL
	in struct VO {
		vec2 uv;
		vec3 base_color;
		vec3 aspect_color;
	} vo;
	out vec4 o_color;	
	void main() {
		float r = length(vo.uv);
		o_color = vec4(vo.base_color, 1 - r);
	}
GLSL
FRAG_PARTICLE_CHECKERS :: #string GLSL
	in struct VO {
		vec2 uv;
		vec3 base_color;
		vec3 aspect_color;
	} vo;
	out vec4 o_color;	
	void main() {
		float r = length(vo.uv);
		o_color = vec4(r < .5 ? vo.aspect_color : vo.base_color, r < 1 ? 1 : 0);
	}
GLSL