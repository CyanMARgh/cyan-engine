GLSL_VERSION_LINE :: #run tprint("\t#version %\n", GL_REQUIRED_VERSION_MAJOR * 100 + GL_REQUIRED_VERSION_MINOR * 10);

Shader_Part :: struct {
	id : u32;
}
Shader :: struct {
	id : u32;	
	extra_fields : Table(string, s32);
	gsx, gsy, gsz : u32 = 1, 1, 1;
}

incldefs :: (sources : ..string) -> string {
	builder := String_Builder.{allocator = temp};
	assert(sources.count >= 1);
	for i : 0..sources.count-2 {
		source := sources[i];
		for line : split(source, cast(u8)#char"\n",, temp) {
			print_to_builder(*builder, "\t/*+*/#define %\n", line);
		}
		append(*builder, "\n");
	}
	append(*builder, sources[sources.count - 1]);
	return builder_to_string(*builder,, temp);	
}
defs :: (lines : ..string) -> string {
	builder := String_Builder.{allocator = temp};
	for lines {
		print_to_builder(*builder, "#define %\n", it);
	}
	return builder_to_string(*builder,, temp);
}
incl :: (sources : ..string) -> string {
	builder := String_Builder.{allocator = temp};
	assert(sources.count >= 1);
	for i : 0..sources.count-2 {
		source := sources[i];
		for line : split(source, cast(u8)#char"\n",, temp) {
			print_to_builder(*builder, "\t/*+*/%\n", line);
		}
		append(*builder, "\n");
	}
	append(*builder, sources[sources.count - 1]);
	return builder_to_string(*builder,, temp);
}

compile_shader_vf :: (src_vert : string, src_frag : string) -> Shader, ok:bool {
	vert, ok := compile_shader_part(src_vert, GL_VERTEX_SHADER);
	if !ok {
		print_color("failed to compile vertex shader\n", color = .RED);
		return .{}, false;
	}
	defer deinit(*vert);
	frag:, ok = compile_shader_part(src_frag, GL_FRAGMENT_SHADER);
	if !ok {
		print_color("failed to compile fragment shader\n", color = .RED);
		return .{}, false;
	}
	defer deinit(*frag);

	using result : Shader;
	id = glCreateProgram();
	glAttachShader(id, vert.id);
	glAttachShader(id, frag.id);
	glLinkProgram(id);

	result, ok = filter_error(result);
	return result, ok;
}
compile_shader_c :: (src_comp : string, gx :u32= 1, gy :u32= 1, gz :u32= 1) -> Shader, ok:bool {
	comp, ok := compile_shader_part(
		incl(
			tprint("layout(local_size_x = %, local_size_y = %, local_size_z = %) in;", gx, gy, gz),
			src_comp
		),
		GL_COMPUTE_SHADER
	);
	if !ok {
		print_color("failed to compile compute shader\n", color = .RED);
		return .{}, false;
	}
	defer deinit(*comp);

	using result := Shader.{gsx = gx, gsy = gy, gsz = gz};
	id = glCreateProgram();
	glAttachShader(id, comp.id);
	glLinkProgram(id);

	result, ok = filter_error(result);
	return result, ok;
}
compute :: (using s : Shader, dimx : u32 = 1, dimy : u32 = 1, dimz : u32 = 1, barrier :u32=GL_ALL_BARRIER_BITS) {
	sizelim :: 10000;
	if dimx > 0 && dimy > 0 && dimz > 0 && dimx < sizelim && dimy < sizelim && dimz < sizelim {
		sx, sy, sz := (dimx - 1) / gsx + 1, (dimy - 1) / gsy + 1, (dimz - 1) / gsz + 1;
		glDispatchCompute(sx, sy, sz);
		if barrier glMemoryBarrier(barrier);		
	}
}
use :: (using s : *Shader) {
	// print("s = %, %\n", s, s.id);
	glUseProgram(id);
}
compile_shader_part :: (_source : string, type : u32) -> Shader_Part, ok:bool {
	source := join(GLSL_VERSION_LINE, _source,, temp);
	id := glCreateShader(type);
	lines := split(source, cast(u8) #char "\n",, temp);

	builder := String_Builder.{allocator = temp};
	for id : 0..lines.count-1 {
		print_to_builder(*builder, "%\n", lines[id]);
	}
	append(*builder, "\0");
	src := builder_to_string(*builder,, temp);
	c_src := src.data;

	glShaderSource(id, 1, *c_src, null);
	glCompileShader(id);

	success : s32;
	info_log_content : [512]s8;
	glGetShaderiv(id, GL_COMPILE_STATUS, *success);
	if !success {
		glGetShaderInfoLog(id, 512, null, cast(*GLchar) *info_log_content);
		info_log := from_c_string(*info_log_content);
		print_color("failed to compile shader: %\n", info_log, color = .RED);
		ok, info_log_parsed := scan("%d(%d)", info_log);
		if info_log_parsed.count >= 2 && info_log_parsed[1].type == type_info(int) {
			error_line := (cast(*int)(info_log_parsed[1].value_pointer)).*;
			source_lines := split(source, "\n",, temp);
			tabbed := true;
			for source_lines if it.count != 0 && it[0] != #char"\t" then tabbed = false;
			RANGE :: 2;
			L0, L1 := max(0, error_line - 1 - RANGE), min(error_line - 1 + RANGE, source_lines.count - 1);
			digits := log10(L1);
			for l : L0..L1 {
				line := source_lines[l];
				if tabbed && line {
					line.count -= 1;
					line.data += 1;
				}
				print_color("[%] %\n", formatInt(l + 1, minimum_digits = digits, padding = #char" "), line, color = .YELLOW);
			}
		} else {
			print_color("unable to parse error message\n", color = .YELLOW);
			print("%\n", src);
		}
		glDeleteShader(id);
		return .{}, false;
	}
	return .{id = id}, true;
}
deinit :: (sp : *Shader_Part) {
	glDeleteShader(sp.id);
}
deinit :: (using s : *Shader) {
	glDeleteProgram(id);
	deinit(*extra_fields);
}

find_id :: (s : *Shader, field : string) -> s32 {
	idptr, new := find_or_add(*s.extra_fields, field);
	if new {
		cstr_field := to_c_string(field);
		<<idptr = glGetUniformLocation(s.id, cstr_field);
		free(cstr_field);
	}
	return <<idptr;
}
set :: (s : *Shader, field : string, value : float) {
	glUniform1f(find_id(s, field), value);
}
set :: (s : *Shader, field : string, value : Vector2) {
	glUniform2f(find_id(s, field), value.x, value.y);
}
set :: (s : *Shader, field : string, value : Vector3) {
	glUniform3f(find_id(s, field), value.x, value.y, value.z);
}
set :: (s : *Shader, field : string, value : Matrix4) {
	glUniformMatrix4fv(find_id(s, field), 1, GL_TRUE, xx *value);
}
set :: (s : *Shader, field : string, value : u32) {
	glUniform1ui(find_id(s, field), value);
}
set :: (s : *Shader, field : string, value : s32) {
	glUniform1i(find_id(s, field), value);
}
set :: (s : *Shader, field : string, value : ivec2) {
	glUniform2i(find_id(s, field), value.x, value.y);
}
set :: (s : *Shader, field : string, value : ivec3) {
	glUniform3i(find_id(s, field), value.x, value.y, value.z);
}

for_expansion :: (shader : *Shader, body : Code, flags : For_Flags) #expand {
	`set :: (name : string, value : $T) #expand {
		set(shader, name, value);
	}
	`compute :: (dimx : u32 = 1, dimy : u32 = 1, dimz : u32 = 1, barrier :u32=GL_ALL_BARRIER_BITS) #expand {
		compute(shader, dimx, dimy, dimz, barrier);
	}
	`it, `it_index := 0;

	use(shader);
	#insert body;
	glUseProgram(0);
}

#scope_file
filter_error :: (using shader : Shader) -> Shader, bool {
	is_linked : GLint;
	glGetProgramiv(id, GL_LINK_STATUS, *is_linked);
	if !is_linked {
		max_length : GLint;
		glGetProgramiv(id, GL_INFO_LOG_LENGTH, xx *max_length);
		info_log := cast(string)NewArray(max_length, u8,, temp);
		glGetProgramInfoLog(id, xx max_length, xx *info_log.count, info_log.data);
		print_color("failed to link shader:\n", color = .RED);
		print_color("%", info_log, color = .YELLOW);
		glDeleteProgram(id);
		return .{}, false;
	}
	return .{id = id}, true;
}